"""Real-PAM tests for the lock-screen stacks (issue #46).

tests/test-pam-sync.sh only reads the PAM files as text, which is how an invalid
`[...] substack` line shipped: every string assertion passed and libpam refused the file on a
real login. These tests load the shipped variants into real libpam through ctypes and run the
exact call sequence of Tinkero's patched Quickshell (PamSubprocess::exec: pam_authenticate,
then pam_acct_mgmt only after a success). The host's password-auth is a fixture in a private
confdir (pam_start_confdir), with the control flow authselect generates but pam_exec checking a
fixed password, so nothing under /etc is read or written.

They need root (pam_faillock writes /run/faillock/<user>), so they run only when euid is 0
inside a container, or when TINKERO_PAM_REAL=1 (CI sets it; then a missing prerequisite is a
failure, not a skip). Locally:
  podman run --rm -v "$PWD:/work:Z" -w /work -e TINKERO_PAM_REAL=1 localhost/tinkero-ci:44 ./dev check
"""
import ctypes
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VARIANTS = ROOT / "distro" / "fedora" / "pam"
SERVICE = "omarchy-lock-password"
USER = "nobody"
SECRET = "right-horse"
WRONG = "wrong-horse"
TALLY = Path("/run/faillock") / USER

PAM_SUCCESS, PAM_AUTH_ERR, PAM_MODULE_UNKNOWN = 0, 7, 28
PAM_PROMPT_ECHO_OFF, PAM_PROMPT_ECHO_ON = 1, 2
MODULE_DIRS = ("/usr/lib64/security", "/usr/lib/security", "/lib/x86_64-linux-gnu/security")
MODULES = ("pam_exec.so", "pam_faillock.so", "pam_deny.so", "pam_permit.so")

REQUIRED = os.environ.get("TINKERO_PAM_REAL") == "1"
IN_CONTAINER = os.path.exists("/run/.containerenv") or os.path.exists("/.dockerenv")
WANTED = REQUIRED or (os.geteuid() == 0 and IN_CONTAINER)


def missing_prerequisite():
    """Why real PAM cannot run here, or None."""
    if os.geteuid() != 0:
        return "needs root: pam_faillock writes /run/faillock"
    try:
        ctypes.CDLL("libpam.so.0").pam_start_confdir
    except (OSError, AttributeError):
        return "no libpam.so.0 with pam_start_confdir (Linux-PAM 1.4 or later)"
    for module in MODULES:
        if not any(os.path.exists(os.path.join(d, module)) for d in MODULE_DIRS):
            return f"no PAM module {module}"
    if shutil.which("faillock") is None:
        return "no faillock command"
    return None


class _Message(ctypes.Structure):
    _fields_ = [("msg_style", ctypes.c_int), ("msg", ctypes.c_char_p)]


class _Response(ctypes.Structure):
    _fields_ = [("resp", ctypes.c_void_p), ("resp_retcode", ctypes.c_int)]


_CONV = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_int,
                         ctypes.POINTER(ctypes.POINTER(_Message)),
                         ctypes.POINTER(ctypes.POINTER(_Response)), ctypes.c_void_p)


class _Conv(ctypes.Structure):
    _fields_ = [("conv", _CONV), ("appdata_ptr", ctypes.c_void_p)]


class Pam:
    """The patched PamSubprocess::exec() call sequence, against a private confdir."""

    def __init__(self, confdir):
        self.confdir = confdir
        self.libc = ctypes.CDLL(None)
        self.libc.calloc.argtypes = [ctypes.c_size_t, ctypes.c_size_t]
        self.libc.calloc.restype = ctypes.c_void_p
        self.libc.strdup.argtypes = [ctypes.c_char_p]
        self.libc.strdup.restype = ctypes.c_void_p
        self.pam = ctypes.CDLL("libpam.so.0")
        self.pam.pam_start_confdir.argtypes = [ctypes.c_char_p, ctypes.c_char_p,
                                               ctypes.POINTER(_Conv), ctypes.c_char_p,
                                               ctypes.POINTER(ctypes.c_void_p)]
        self.pam.pam_authenticate.argtypes = [ctypes.c_void_p, ctypes.c_int]
        self.pam.pam_acct_mgmt.argtypes = [ctypes.c_void_p, ctypes.c_int]
        self.pam.pam_end.argtypes = [ctypes.c_void_p, ctypes.c_int]

    def unlock(self, password, account=True):
        """Return (auth result, account result or None). The account phase runs only after a
        successful auth, as in the patched Quickshell; account=False is the unpatched one."""
        libc = self.libc

        def conv(count, messages, responses, _appdata):
            # PAM frees the array and each answer, so both come from the C allocator.
            array = ctypes.cast(libc.calloc(count, ctypes.sizeof(_Response)),
                                ctypes.POINTER(_Response))
            for i in range(count):
                if messages[i].contents.msg_style in (PAM_PROMPT_ECHO_OFF, PAM_PROMPT_ECHO_ON):
                    array[i].resp = libc.strdup(password.encode())
            responses[0] = array
            return PAM_SUCCESS

        callback = _CONV(conv)
        pam_conv = _Conv(callback, None)
        handle = ctypes.c_void_p()
        rc = self.pam.pam_start_confdir(SERVICE.encode(), USER.encode(), ctypes.byref(pam_conv),
                                        self.confdir.encode(), ctypes.byref(handle))
        if rc != PAM_SUCCESS:
            raise RuntimeError(f"pam_start_confdir failed: {rc}")
        auth = self.pam.pam_authenticate(handle, 0)
        acct = None
        if auth == PAM_SUCCESS and account:
            acct = self.pam.pam_acct_mgmt(handle, 0)
        self.pam.pam_end(handle, auth if acct is None else acct)
        return auth, acct


def tally():
    """Failures on USER's tally: `faillock --user` prints a name line and a header, then one
    line per recorded failure."""
    out = subprocess.run(["faillock", "--user", USER], capture_output=True, text=True,
                         check=True).stdout
    return len([line for line in out.splitlines()[2:] if line.strip()])


def host_password_auth(check, with_faillock):
    """A fixture password-auth with authselect's control flow ("local" profile, optionally
    with-faillock), where pam_exec checks the password instead of pam_unix. deny=3 is spelled
    out so the fixture does not depend on the image's /etc/security/faillock.conf."""
    lines = []
    if with_faillock:
        lines.append("auth     required    pam_faillock.so preauth silent deny=3")
    lines.append(f"auth     sufficient  pam_exec.so quiet expose_authtok {check}")
    if with_faillock:
        lines.append("auth     required    pam_faillock.so authfail deny=3")
    lines.append("auth     required    pam_deny.so")
    if with_faillock:
        lines.append("account  required    pam_faillock.so")
    lines.append("account  required    pam_permit.so")
    return "\n".join(lines) + "\n"


@unittest.skipUnless(WANTED, "real PAM runs as root in a container, or with TINKERO_PAM_REAL=1: "
                     "podman run --rm -v \"$PWD:/work:Z\" -w /work -e TINKERO_PAM_REAL=1 "
                     "localhost/tinkero-ci:44 ./dev check")
class RealPam:
    """Shared cases; subclasses name the variant, the host it is written for and its deny."""
    variant = None
    with_faillock = None
    deny = None

    def setUp(self):
        reason = missing_prerequisite()
        if reason:
            if REQUIRED:
                self.fail(f"TINKERO_PAM_REAL=1 but {reason}")
            self.skipTest(reason)
        self.dir = tempfile.mkdtemp(prefix="tinkero-pam.")
        self.addCleanup(shutil.rmtree, self.dir)
        check = os.path.join(self.dir, "check-password")
        with open(check, "w") as f:
            f.write(f'#!/bin/bash\nIFS= read -r token\n[[ $token == "{SECRET}" ]]\n')
        os.chmod(check, 0o755)
        with open(os.path.join(self.dir, "password-auth"), "w") as f:
            f.write(host_password_auth(check, self.with_faillock))
        shutil.copy(VARIANTS / f"omarchy-lock-password.{self.variant}",
                    os.path.join(self.dir, SERVICE))
        TALLY.parent.mkdir(parents=True, exist_ok=True)
        TALLY.unlink(missing_ok=True)
        self.addCleanup(TALLY.unlink, missing_ok=True)
        self.pam = Pam(self.dir)

    def test_correct_password_unlocks(self):
        self.assertEqual(self.pam.unlock(SECRET), (PAM_SUCCESS, PAM_SUCCESS))
        self.assertEqual(tally(), 0)

    def test_wrong_password_refused_and_counted_once(self):
        for expected in (1, 2):
            self.assertEqual(self.pam.unlock(WRONG), (PAM_AUTH_ERR, None))
            self.assertEqual(tally(), expected)

    def test_auth_only_does_not_clear_tally(self):
        # An unpatched Quickshell never runs the account phase: the file still unlocks and
        # counts, but the tally stays (the reason for the Quickshell patch, issue #46).
        self.pam.unlock(WRONG)
        self.pam.unlock(WRONG)
        self.assertEqual(self.pam.unlock(SECRET, account=False), (PAM_SUCCESS, None))
        self.assertEqual(tally(), 2)

    def test_account_phase_clears_tally(self):
        self.pam.unlock(WRONG)
        self.pam.unlock(WRONG)
        self.assertEqual(self.pam.unlock(SECRET), (PAM_SUCCESS, PAM_SUCCESS))
        self.assertEqual(tally(), 0)

    def test_lockout_refuses_correct_password(self):
        for _ in range(self.deny):
            self.assertEqual(self.pam.unlock(WRONG), (PAM_AUTH_ERR, None))
        self.assertEqual(tally(), self.deny)
        auth, acct = self.pam.unlock(SECRET)
        self.assertNotEqual(auth, PAM_SUCCESS, "a locked account must not unlock")
        self.assertIsNone(acct)
        self.assertEqual(tally(), self.deny, "a refused unlock must not clear the tally")

    def test_invalid_substack_is_detected(self):
        # The #46 construct, loaded by the same harness: proves the harness sees what text
        # checks could not (libpam dlopens a module named "substack": PAM_MODULE_UNKNOWN).
        with open(os.path.join(self.dir, SERVICE), "w") as f:
            f.write("auth  [success=1 default=bad]  substack  password-auth\n"
                    "auth  required  pam_deny.so\n")
        self.assertEqual(self.pam.unlock(SECRET)[0], PAM_MODULE_UNKNOWN)


class WrappedVariant(RealPam, unittest.TestCase):
    variant, with_faillock, deny = "wrapped", False, 10


class PlainVariant(RealPam, unittest.TestCase):
    variant, with_faillock, deny = "plain", True, 3


if __name__ == "__main__":
    unittest.main()
