# Issue #46: lock-screen PAM fix (account-phase reset) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Both lock-screen PAM variants authenticate again (right password unlocks, wrong refused, each failure counted once, tally cleared on success). A test running real libpam proves it and keeps the bug from coming back.

**Architecture:** `[...] substack` is invalid PAM (libpam dlopens a module literally named `substack`), and no static PAM file can run `password-auth` and then branch on its result. So the tally reset moves out of the auth phase and into the standard place: `account required pam_faillock.so`. Tinkero's Quickshell RPM gets a one-file patch so that `PamSubprocess::exec()` calls `pam_acct_mgmt` after a successful `pam_authenticate`. That call was always missing; PR #43 wrongly assumed it needs root. The two variants become plain `include password-auth` stacks. A new Python test drives real libpam through ctypes against the shipped files in a fixture confdir.

**Tech Stack:** Linux-PAM 1.7 (Fedora 44), bash, Python 3 stdlib (ctypes, unittest), RPM spec, C++ (a single hunk in Quickshell).

**Spec:** issue #46 (`gh issue view 46 --comments`), design spec `docs/superpowers/specs/2026-09-17-tinkero-design.md` section 4.8. Decision record D1 to D7 below (operator-delegated, binding for this plan).

## Decision record (binding)

- **D1 account result:** after `pam_authenticate == PAM_SUCCESS`, call `pam_acct_mgmt(handle, 0)`. `PAM_SUCCESS` -> `Success`. `PAM_NEW_AUTHTOK_REQD` -> `Success`, logged unconditionally ("password expired; unlocking anyway, the lock screen cannot change it"). Any other code -> `PamIpcExitCode::PamError`, logged unconditionally with `pam_strerror` ("refusing"). The account result goes to `pam_end`. No new enum value.
- **D2 scope:** unconditional for every PamContext (no env var, no config gate). For the fingerprint service the faillock account hook is a no-op.
- **D3 install guarantee:** `quickshell.spec` `Release: 2`, changelog entry and header deviation bullet; new lock key `quickshell_release=2`; `tinkero.spec.in` gets `Requires:       (quickshell = @QUICKSHELL@ with quickshell >= @QUICKSHELL@-@QUICKSHELL_RELEASE@)`; `tests/test-specs.sh` checks that the spec's Release and commit match the lock. Do not bump `tinkero_rev`.
- **D4 tests:** new `tests/test_pam_real.py` (ctypes, stdlib only). It runs when euid is 0 inside a container, or when `TINKERO_PAM_REAL=1` is set (then a missing prerequisite is a FAILURE, not a skip). CI sets `TINKERO_PAM_REAL=1` on `./dev check`. `tests/test-pam-sync.sh` text asserts are rewritten for the new shape. Quickshell is not rebuilt in CI; a CI step proves the patch applies (`%prep`), and one full compile is done by hand and recorded in the PR.
- **D5 COPR:** this task does not trigger `copr-build`. The PR says COPR must rebuild `quickshell` then `tinkero` before #37.
- **D6 counter +2:** not fixed here and no new issue. It comes from the PAM_MODULE_UNKNOWN error path, which fires both `onError` and `completed`. With the fix, a wrong password returns PAM_AUTH_ERR and counts +1. #37 checks it.
- **D7 docs:** spec 4.1, 4.7, 4.8, 4.12; `docs/guides/phase-2f-vm-check.md` section 3; `distro/fedora/specs/README.md`; the PAM file headers; `quickshell.spec` header. Historical plans stay as they are.

## Global Constraints

- bash scripts: `set -euo pipefail`, ShellCheck clean (`shellcheck -x -e SC1090,SC1091`).
- Python: standard library only.
- No em dashes (U+2014) in any Tinkero-authored text (`./dev gates` branding gate).
- Tests never touch the network or run a real package manager.
- Allowlists under `ci/allow/` only shrink.
- Never push `master`. Commit on the current branch `task/e400a080` only.
- The authoritative verification is local, in the Fedora 44 image, **as root** (so the real-PAM test runs):
  `podman run --rm -v "$PWD:/work:Z" -w /work -e TINKERO_PAM_REAL=1 localhost/tinkero-ci:44 bash -c './dev check'`
  and `./dev gates` in the same image. Ignore GitHub Actions results (billing wall).

## Review Focus

1. **Unpatched Quickshell with the new files** (a `-1` build still installed): the files must still authenticate correctly and count once; only the reset is missing. Pinned by `test_auth_only_does_not_clear_tally` (Task 1).
2. **Locked account plus the correct password**: must be refused and must not clear the tally, in both variants. Pinned by `test_lockout_refuses_correct_password` (Task 1).
3. **Account phase refuses after a correct password** (expired account, pam_access): the unlock must be refused (D1), except an expired *password*, which unlocks. This lives in C++ and has no unit test; the Task 2 reviewer and the final review check the patch hunk against D1 line by line.
4. **A bracketed control on `include` or `substack` reappearing** in any shipped PAM file: a text guard in `tests/test-pam-sync.sh` (Task 1), plus `test_invalid_substack_is_detected` proving the harness itself sees code 28.
5. **A stale `quickshell-...-1` build satisfying the dependency**: pinned by the render-spec assertion on the rich `with` Requires (Task 2).

---

### Task 1: Real-PAM test, new PAM variants, text guards (model: sonnet)

**Files:**
- Create: `tests/test_pam_real.py`
- Modify: `distro/fedora/pam/omarchy-lock-password.wrapped` (whole file)
- Modify: `distro/fedora/pam/omarchy-lock-password.plain` (whole file)
- Modify: `tests/test-pam-sync.sh` (the block headed `# --- the packaged variants reset the tally in the auth phase (issue #29)`)
- Modify: `.github/workflows/ci.yml` (the `Unit tests` step)

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: `tests/test_pam_real.py`, picked up by `tests/run` (it runs `python3 -m unittest discover -s tests -p 'test_*.py'`). Env var `TINKERO_PAM_REAL=1` means the test must run.

- [ ] **Step 1: Write the real-PAM test**

Create `tests/test_pam_real.py` with exactly this content:

```python
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
```

- [ ] **Step 2: Run it against the current (broken) files and confirm it fails**

Run (from the worktree, container as root):
`podman run --rm -v "$PWD:/work:Z" -w /work -e TINKERO_PAM_REAL=1 localhost/tinkero-ci:44 python3 -m unittest tests.test_pam_real -v`
Expected: FAIL. The correct-password, lockout and tally cases fail with auth result 28 (`PAM_MODULE_UNKNOWN`). `test_invalid_substack_is_detected` passes in both classes. If anything errors instead (a ctypes or prerequisite problem), fix the harness before going on.

- [ ] **Step 3: Rewrite the wrapped variant**

Replace `distro/fedora/pam/omarchy-lock-password.wrapped` with exactly:

```
#%PAM-1.0
# omarchy-lock-password, variant "wrapped": written by tinkero-pam-sync because this host's
# password-auth has no pam_faillock. Do not edit; run `sudo tinkero-pam-sync` after changing
# authselect features. Design spec 4.8.
#
# password-auth is pulled in with `include`. On a correct password its `sufficient` line ends
# the stack before authfail; a wrong one falls through its pam_deny to authfail, is recorded
# once, and `[default=die]` stops there. The tally is cleared in the account phase by
# `account required pam_faillock.so`. The lock runs that phase because Tinkero's quickshell
# build (release 2 or later) calls pam_acct_mgmt after a successful pam_authenticate. Under an
# unpatched quickshell this file still authenticates and counts, but never clears the tally.
# No static file can clear it in the auth phase instead: libpam gives the parent stack no
# result to branch on after `include` or `substack`, and neither takes a bracketed control
# (issue #46).
auth     required       pam_faillock.so preauth silent deny=10 unlock_time=120
auth     include        password-auth
auth     [default=die]  pam_faillock.so authfail deny=10 unlock_time=120
auth     required       pam_deny.so
account  required       pam_faillock.so
account  include        password-auth
```

- [ ] **Step 4: Rewrite the plain variant**

Replace `distro/fedora/pam/omarchy-lock-password.plain` with exactly:

```
#%PAM-1.0
# omarchy-lock-password, variant "plain": written by tinkero-pam-sync because this host's
# password-auth already runs pam_faillock. Do not edit; run `sudo tinkero-pam-sync` after
# changing authselect features. Design spec 4.8.
#
# password-auth does all the work: its own preauth and authfail count a wrong password once,
# and its `account required pam_faillock.so` clears the tally after a correct one. The lock
# runs that account phase because Tinkero's quickshell build (release 2 or later) calls
# pam_acct_mgmt after a successful pam_authenticate. Under an unpatched quickshell this file
# still authenticates and counts, but never clears the tally (issue #46).
auth     include  password-auth
account  include  password-auth
```

- [ ] **Step 5: Run the real-PAM test again and confirm it passes**

Run: `podman run --rm -v "$PWD:/work:Z" -w /work -e TINKERO_PAM_REAL=1 localhost/tinkero-ci:44 python3 -m unittest tests.test_pam_real -v`
Expected: 12 tests, all `ok`, none skipped.

Also confirm the skip path on the host (not root, not in a container):
Run: `python3 -m unittest tests.test_pam_real -v`
Expected: every test `skipped` with the podman hint, exit 0.

- [ ] **Step 6: Rewrite the text guards in `tests/test-pam-sync.sh`**

Replace the whole block from the line `# --- the packaged variants reset the tally in the auth phase (issue #29) ---...` down to and including the line `assert_eq "$(grep -Ec 'pam_faillock\.so (preauth|authfail)' "$p")" "0" "plain: adds no preauth/authfail, so it never double-counts the host's own faillock"` with:

```bash
# --- the packaged variants (issue #46) --------------------------------------------------------
# tests/test_pam_real.py runs these files through real libpam; the text checks below only pin
# their shape. The tally reset is the account phase's `pam_faillock.so`, which the lock runs
# through Tinkero's patched quickshell (pam_acct_mgmt), so neither file needs authsucc.
w=$ROOT/distro/fedora/pam/omarchy-lock-password.wrapped
p=$ROOT/distro/fedora/pam/omarchy-lock-password.plain
active() { grep -vE '^[[:space:]]*(#|$)' "$1"; }
assert_contains "$(active "$w")" "pam_faillock.so preauth silent deny=10 unlock_time=120" "wrapped: preauth with upstream's deny=10 unlock_time=120"
assert_contains "$(active "$w")" "include        password-auth" "wrapped: the host stack comes in with include"
assert_contains "$(active "$w")" "[default=die]  pam_faillock.so authfail deny=10 unlock_time=120" "wrapped: a wrong password is recorded once and dies at authfail"
assert_contains "$(active "$w")" "account  required       pam_faillock.so" "wrapped: the account phase clears the tally"
assert_eq "$(active "$w" | grep -c 'authsucc' || true)" "0" "wrapped: no authsucc (the reset is the account phase's)"
assert_eq "$(active "$w" | grep -E '^account' | awk '{print $2}' | tr '\n' ' ')" "required include " "wrapped: account pam_faillock comes before account include password-auth"
assert_eq "$(active "$p")" "$(printf 'auth     include  password-auth\naccount  include  password-auth')" "plain: exactly the two include lines"
# the #46 class of bug: a bracketed control on include/substack is invalid PAM, and substack is
# not used at all any more
for f in "$ROOT"/distro/fedora/pam/*; do
  n=$(basename "$f")
  assert_eq "$(active "$f" | grep -cE '^[[:space:]]*-?[a-z]+[[:space:]]+\[[^]]*\][[:space:]]+(include|substack)\b' || true)" "0" "$n: no bracketed control on include/substack"
  assert_eq "$(active "$f" | grep -c 'substack' || true)" "0" "$n: no substack line"
done
```

- [ ] **Step 7: Make CI require the real-PAM test**

In `.github/workflows/ci.yml`, change the `Unit tests` step to:

```yaml
      - name: Unit tests
        # TINKERO_PAM_REAL=1: tests/test_pam_real.py must run (the job is root in a container);
        # a missing prerequisite fails the job instead of skipping it.
        env:
          TINKERO_PAM_REAL: "1"
        run: ./dev check
```

- [ ] **Step 8: Full check as root in the image**

Run: `podman run --rm -v "$PWD:/work:Z" -w /work -e TINKERO_PAM_REAL=1 localhost/tinkero-ci:44 bash -c 'shellcheck -x -e SC1090,SC1091 tests/test-pam-sync.sh distro/fedora/bin/* && ./dev check'`
Expected: exit 0, no `not ok` line, the Python summary shows `OK` with 12 more tests than before.

- [ ] **Step 9: Commit**

```bash
git add tests/test_pam_real.py tests/test-pam-sync.sh distro/fedora/pam/omarchy-lock-password.wrapped distro/fedora/pam/omarchy-lock-password.plain .github/workflows/ci.yml
git commit -m "pam: include password-auth in both lock variants, test them against real libpam" -m "Closes #46"
```

---

### Task 2: Quickshell pam_acct_mgmt patch, release pin (model: sonnet)

**Files:**
- Create: `distro/fedora/specs/quickshell-pam-acct-mgmt.patch`
- Modify: `distro/fedora/specs/quickshell.spec` (header comment, `Release:`, a `Patch0:` line after `Source0:`, `%changelog`)
- Modify: `upstream.lock` (new key after `quickshell_commit=`)
- Modify: `build/render-spec`, `tinkero.spec.in:15`, `tests/test-render-spec.sh`, `tests/test-specs.sh`
- Modify: `distro/fedora/specs/README.md:12` and `:26`
- Modify: `.github/workflows/ci.yml` (one new step)

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: lock key `quickshell_release` (integer) and placeholder `@QUICKSHELL_RELEASE@`. Task 3 documents both.

- [ ] **Step 1: Make the patch**

A clean checkout of Quickshell at the pinned commit is at
`/tmp/claude-1000/-home-diego-worktrees-tinkero-e400a080/6f20ebd7-efa3-4917-b8e6-a0d7fab59437/scratchpad/qs`
(`git -C <that> rev-parse HEAD` must print `28771c7c74b42e20afca0b1b63980cb46515537c`; if the directory is missing, `git clone https://github.com/quickshell-mirror/quickshell` and check out that commit). In `src/services/pam/subprocess.cpp`, replace the `case PAM_SUCCESS:` arm of the switch after `result = pam_authenticate(handle, 0);`:

```cpp
	case PAM_SUCCESS:
		logIf(this->log) << "Authenticated successfully." << std::endl;
		code = PamIpcExitCode::Success;
		break;
```

with:

```cpp
	case PAM_SUCCESS:
		logIf(this->log) << "Authenticated successfully." << std::endl;
		// Tinkero: run the account phase too, the sequence PAM documents after
		// pam_authenticate. pam_faillock clears its tally there, and the host's account
		// policy (expiry, pam_access) applies to an unlock as it does to a login.
		result = pam_acct_mgmt(handle, 0);
		switch (result) {
		case PAM_SUCCESS: code = PamIpcExitCode::Success; break;
		case PAM_NEW_AUTHTOK_REQD:
			logIf(true) << "Account check: password expired (code " << result
			            << "); unlocking anyway, the lock screen cannot change it." << std::endl;
			code = PamIpcExitCode::Success;
			break;
		default:
			logIf(true) << "Account check failed after successful authentication: \""
			            << pam_strerror(handle, result) << "\" (code " << result << "); refusing."
			            << std::endl;
			code = PamIpcExitCode::PamError;
			break;
		}
		break;
```

Leave everything else unchanged (the later `result = pam_end(handle, result);` now receives the account result, as D1 requires). Then:
`git -C <qs> diff > /home/diego/worktrees/tinkero/e400a080/distro/fedora/specs/quickshell-pam-acct-mgmt.patch` and `git -C <qs> checkout -- .` to leave the checkout clean. The patch must have `a/src/services/pam/subprocess.cpp` / `b/...` paths (applies with `-p1` inside `quickshell-<commit>/`). Put this header before the `diff --git` line:

```
Tinkero: call pam_acct_mgmt after a successful pam_authenticate (issue #46).

PamSubprocess::exec() ran only the auth phase, so pam_faillock's account-phase reset never ran
for the lock screen and earlier failures stayed on the tally after a correct unlock. An
expired password (PAM_NEW_AUTHTOK_REQD) still unlocks; any other account failure refuses.
Drop this patch once upstream Quickshell calls pam_acct_mgmt.

```

- [ ] **Step 2: Wire it into quickshell.spec**

- `Release:            1%{?dist}` becomes `Release:            2%{?dist}`.
- After the `Source0:` line add:
  ```
  # Tinkero: run PAM's account phase after authentication, so pam_faillock's tally reset runs
  # under the lock screen (issue #46). Applied by %autosetup -p1.
  Patch0:             quickshell-pam-acct-mgmt.patch
  ```
- In the header's deviation list (the `#   * ...` bullets after "with these deviations:"), add a first bullet:
  ```
  #   * Patch0 quickshell-pam-acct-mgmt.patch: PamContext also calls pam_acct_mgmt
  #                              after a successful pam_authenticate (Tinkero issue #46).
  ```
  Write that bullet with a colon as shown, not a dash, even though the neighbouring forked lines use em dashes: new Tinkero text never carries one.
- Put a new first entry at the top of `%changelog`:
  ```
  * Mon Sep 28 2026 Tinkero <noreply@tinkero> - 0.3.0^20.git28771c7-2
  - Call pam_acct_mgmt after a successful pam_authenticate, so the lock screen's
    pam_faillock tally resets on unlock (issue #46).

  ```

- [ ] **Step 3: Prove the patch applies to the pinned tarball (manual, network allowed)**

Run:
```bash
podman run --rm -v "$PWD:/work:Z" -w /work localhost/tinkero-ci:44 bash -c '
  set -e; mkdir -p /tmp/s /tmp/t
  make -f .copr/Makefile srpm spec=distro/fedora/specs/quickshell.spec outdir=/tmp/s
  rpm -i --define "_topdir /tmp/t" /tmp/s/*.src.rpm
  rpmbuild -bp --nodeps --define "_topdir /tmp/t" /tmp/t/SPECS/quickshell.spec
  grep -n "pam_acct_mgmt" /tmp/t/BUILD/quickshell-*/src/services/pam/subprocess.cpp'
```
Expected: `%prep` succeeds, and the grep prints the new `pam_acct_mgmt(handle, 0)` line. (If `srpm.sh` needs tools missing from the image, `dnf -y install` them inside this throwaway container; that is fine here, it is not a test.)

- [ ] **Step 4: Add the lock key and the rendered dependency (test first)**

In `tests/test-render-spec.sh`, add `quickshell_release=2` after the `quickshell=` line in **both** heredocs (the initial one and `reset_lock`), and change the quickshell assertion to:

```bash
assert_contains "$s" "Requires:       (quickshell = 0.3.0^20.git28771c7 with quickshell >= 0.3.0^20.git28771c7-2)" "quickshell pin is verbatim and needs Tinkero's patched release"
```

and add, next to the other rejection cases:

```bash
reset_lock
sed -i 's/^quickshell_release=.*/quickshell_release=2a/' "$d/lock"
out=$(r 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 1 "a non-integer quickshell_release is rejected"
assert_contains "$out" "quickshell_release must be an integer" "by the validator"
```

Run `bash tests/test-render-spec.sh`: expect the new assertions to fail.

Then:
- `upstream.lock`: add `quickshell_release=2` on the line after `quickshell_commit=...`.
- `build/render-spec`: after the `rev=$(lock_get tinkero_rev "$lock")` line add `qsrel=$(lock_get quickshell_release "$lock")`; after the `tinkero_rev` validation add `[[ $qsrel =~ ^[0-9]+$ ]] || die "quickshell_release must be an integer: $qsrel"`; add `-e "s|@QUICKSHELL_RELEASE@|$qsrel|g"` to the sed.
- `tinkero.spec.in` line 15 becomes: `Requires:       (quickshell = @QUICKSHELL@ with quickshell >= @QUICKSHELL@-@QUICKSHELL_RELEASE@)`, with this comment line right above it: `# The release floor is Tinkero's patched build (pam_acct_mgmt for the lock screen, issue #46).`

Run `bash tests/test-render-spec.sh`: all `ok`.

- [ ] **Step 5: Keep the spec and the lock consistent (test)**

In `tests/test-specs.sh`, after the `herdr patch present` line add:

```bash
assert_file "$D/quickshell-pam-acct-mgmt.patch" "quickshell patch present"
assert_contains "$(cat "$D/quickshell.spec")" "Patch0:             quickshell-pam-acct-mgmt.patch" "quickshell.spec applies the pam_acct_mgmt patch"
lock=$ROOT/upstream.lock
qs_rel=$(grep -m1 -E '^Release:' "$D/quickshell.spec" | awk '{print $2}' | sed 's/%.*//')
assert_eq "$qs_rel" "$(grep -E '^quickshell_release=' "$lock" | cut -d= -f2)" "quickshell.spec Release matches the lock's quickshell_release"
qs_commit=$(grep -m1 -E '^%global commit ' "$D/quickshell.spec" | awk '{print $3}')
assert_eq "$qs_commit" "$(grep -E '^quickshell_commit=' "$lock" | cut -d= -f2)" "quickshell.spec commit matches the lock's quickshell_commit"
```

Run `bash tests/test-specs.sh`: all `ok`.

- [ ] **Step 6: README and CI step**

- `distro/fedora/specs/README.md`: "The 24 other specs are byte-identical to" becomes "The 23 other specs are byte-identical to"; the fork-changes sentence gets a clause "`quickshell` later gained `quickshell-pam-acct-mgmt.patch` (issue #46)". The layout bullet `` - `macros.hyprland`, `herdr-libvt-only.patch`: local sources two specs need. `` becomes `` - `macros.hyprland`, `herdr-libvt-only.patch`, `quickshell-pam-acct-mgmt.patch`: local sources three specs need. `` Reflow the lines to about 95 columns, as the file does.
- `.github/workflows/ci.yml`: after the `A vendored (Rust) package SRPM builds...` step add:

```yaml
      - name: The Quickshell patch applies to the pinned tarball (issue #46)
        run: |
          mkdir -p "$PWD/.cache/srpm-quickshell" "$PWD/.cache/rpmbuild-quickshell"
          make -f .copr/Makefile srpm spec=distro/fedora/specs/quickshell.spec outdir="$PWD/.cache/srpm-quickshell"
          rpm -i --define "_topdir $PWD/.cache/rpmbuild-quickshell" .cache/srpm-quickshell/*.src.rpm
          rpmbuild -bp --nodeps --define "_topdir $PWD/.cache/rpmbuild-quickshell" .cache/rpmbuild-quickshell/SPECS/quickshell.spec
          grep -q 'pam_acct_mgmt' .cache/rpmbuild-quickshell/BUILD/quickshell-*/src/services/pam/subprocess.cpp
```

- [ ] **Step 7: Full check and spec parse**

Run: `podman run --rm -v "$PWD:/work:Z" -w /work -e TINKERO_PAM_REAL=1 localhost/tinkero-ci:44 bash -c 'shellcheck -x -e SC1090,SC1091 build/render-spec tests/test-render-spec.sh tests/test-specs.sh && ./dev check && ./dev spec && rpmspec -P tinkero.spec | grep -n "quickshell" && rpmspec -P distro/fedora/specs/quickshell.spec | grep -nE "^(Release|Patch0)" && rpmlint distro/fedora/specs/quickshell.spec; rm -f tinkero.spec'`
Expected: exit 0 from `./dev check`; the rendered Requires shows `quickshell >= 0.3.0^20.git28771c7-2`; `Release: 2.fc44` (or `2`) and `Patch0` present; rpmlint reports no more errors than it does for `git show origin/master:distro/fedora/specs/quickshell.spec` saved to a temp file.

- [ ] **Step 8: Commit**

```bash
git add distro/fedora/specs/quickshell-pam-acct-mgmt.patch distro/fedora/specs/quickshell.spec distro/fedora/specs/README.md upstream.lock build/render-spec tinkero.spec.in tests/test-render-spec.sh tests/test-specs.sh .github/workflows/ci.yml
git commit -m "quickshell: call pam_acct_mgmt after authentication; require the patched release (#46)"
```

---

### Task 3: One full Quickshell compile with the patch (model: haiku, background)

**Files:** none changed. Output: a log in the scratchpad and one line for the PR body.

**Interfaces:**
- Consumes: Task 2's committed `quickshell.spec` and patch.

- [ ] **Step 1: Build the SRPM and rebuild it in a throwaway Fedora 44 container**

Run (it takes a long time; run it in the background and wait for it):
```bash
podman run --rm -v "$PWD:/work:Z" -w /work fedora:44 bash -c '
  set -e; dnf -y -q install git-core make rpm-build rpmdevtools dnf-plugins-core curl
  mkdir -p /tmp/s
  make -f .copr/Makefile srpm spec=distro/fedora/specs/quickshell.spec outdir=/tmp/s
  dnf -y -q builddep /tmp/s/*.src.rpm
  rpmbuild --rebuild /tmp/s/*.src.rpm 2>&1 | tail -20
  ls -l /root/rpmbuild/RPMS/x86_64/' > /tmp/claude-1000/-home-diego-worktrees-tinkero-e400a080/6f20ebd7-efa3-4917-b8e6-a0d7fab59437/scratchpad/quickshell-build.log 2>&1; echo "exit=$?"
```
Expected: `exit=0`, and the log ends with `quickshell-0.3.0^20.git28771c7-2.fc44.x86_64.rpm` listed. Report the exit code, the last 20 lines of the log and the RPM file names. Do not change any file in the repo.

---

### Task 4: Docs (model: sonnet)

**Files:**
- Modify: `docs/superpowers/specs/2026-09-17-tinkero-design.md` sections 4.1 (around line 76-80), 4.7 (starts line 203), 4.8 (lines 226-262), 4.12 (starts line 285)
- Modify: `docs/guides/phase-2f-vm-check.md` section 3, "The lock screen" (around lines 205-232)

**Interfaces:**
- Consumes: the final file contents from Tasks 1 and 2 (read them from the tree; do not paraphrase them from memory).

- [ ] **Step 1: Spec 4.8**

- In the "A failure is counted once." bullet, keep the reasoning but drop nothing true.
- Replace the fenced design block with the two new files' active lines (copy them from `distro/fedora/pam/`, without the comment headers).
- Replace the paragraph starting "**The reset runs in the auth phase, not the account phase.**" with a paragraph headed "**The reset runs in the account phase, which Tinkero's Quickshell build runs.**" that says, in Tinkero's plain style and with no em dash:
  - The Quickshell lock authenticates through `PamContext`. At the pinned commit it runs only `pam_authenticate`, so `pam_faillock`'s reset-on-success (`account required pam_faillock.so`) never ran (issue #29).
  - Issue #29's first fix reset with `authsucc` in the auth phase and pulled `password-auth` in as `[success=...] substack`. That line is invalid: `substack` and `include` take no bracketed control, and libpam loaded a module literally named `substack`, so nobody could unlock (issue #46). No valid static file can do it either: after an `include` or `substack` the parent stack has no result to branch on, so a trailing `authsucc` either runs after a wrong password too (clearing the tally, which removes the lockout) or never runs. This was checked against real libpam.
  - The fix is the standard one: Tinkero's `quickshell` RPM carries `quickshell-pam-acct-mgmt.patch`, which calls `pam_acct_mgmt` after a successful `pam_authenticate`. PR #43's belief that the account phase needs root was wrong: it runs unprivileged (`pam_unix` uses the same `unix_chkpwd` helper as the auth phase). Semantics: success unlocks; an expired password (`PAM_NEW_AUTHTOK_REQD`) still unlocks and is logged; any other account failure refuses the unlock, as a fresh login would be refused. It applies to every `PamContext`, including the fingerprint service, where `pam_faillock`'s account hook does nothing.
  - Wrapped: a wrong password is recorded once by the outer `authfail` and `[default=die]` stops there; a correct one ends the stack at `password-auth`'s `sufficient` line. Plain: `password-auth`'s own faillock counts once and its own account line resets. No double count in either.
  - Under an unpatched Quickshell the files still authenticate and count; only the reset is missing, so the build order is a dependency question, not a safety one. `tinkero` requires `quickshell >= <version>-<quickshell_release>` (4.12).
  - `tests/test_pam_real.py` runs both variants through real libpam in CI.
  - Keep the existing sentences about toggling `with-faillock` and `tinkero-status` (drift), and the tmpfiles.d paragraph, unchanged, except "The `account` lines are kept but are dead under the lock" must go (they are live now).
- In the closing sentence of the tmpfiles.d paragraph, "the auth-phase reset, the `substack` behavior and the `tmpfiles.d` tally seeding" becomes "the account-phase reset under the patched Quickshell and the `tmpfiles.d` tally seeding".

- [ ] **Step 2: Spec 4.1, 4.7, 4.12**

- 4.1: the example `Requires: quickshell = 0.3.0^20.git28771c7` becomes `Requires: (quickshell = 0.3.0^20.git28771c7 with quickshell >= 0.3.0^20.git28771c7-2)`, with one sentence after the block: the release floor is Tinkero's own patched build (4.8), taken from the lock's `quickshell_release`.
- 4.7: in the list of what a bump involves (find the Quickshell or "bump" steps), add: "rebase `quickshell-pam-acct-mgmt.patch` onto the new snapshot, and drop it once upstream Quickshell calls `pam_acct_mgmt` (4.8)".
- 4.12: add `quickshell_release=2` to the lock listing after `quickshell_commit=`, and a bullet: "`quickshell_release`: the lowest `quickshell` RPM release `tinkero` accepts, the first one carrying Tinkero's patch (4.8); `tests/test-specs.sh` checks it equals `quickshell.spec`'s `Release:`."

- [ ] **Step 3: VM guide section 3**

In `docs/guides/phase-2f-vm-check.md`, "The lock screen":
- Before the first lock checkbox add a checkbox: `` `rpm -q quickshell` prints `quickshell-0.3.0^20.git28771c7-2.fc44.x86_64` (Tinkero's build with the account-phase patch, #46) ``.
- Add a checkbox after "the lock appears and refuses both wrong passwords": "the on-screen counter reads `(1)` after the first wrong password and `(2)` after the second (#46 saw +2 per attempt; that came from the broken file's error path)".
- The parenthetical "(#29, second defect: the unlock never reset the tally; the `wrapped` variant now resets with `pam_faillock authsucc` in the auth phase)" becomes "(#29, second defect, fixed by #46: the lock now runs the account phase, whose `pam_faillock` resets the tally)".
- Add a first-try unlock checkbox: "the right password unlocks on the first try (#46: before the fix, no password did)".
- Add a checkbox: `` `journalctl --user -b | grep -i "module is unknown"` prints nothing ``.
- The plain-variant parenthetical "(the `plain` variant's `authsucc`, #29)" becomes "(`password-auth`'s own account-phase `pam_faillock`, run by the patched Quickshell, #46)".
- Add a line under the section's checks: "Fingerprint unlock is not checked (the VM has no reader); the account phase applies to it too (spec 4.8)."

- [ ] **Step 4: Check**

Run: `podman run --rm -v "$PWD:/work:Z" -w /work localhost/tinkero-ci:44 bash -c './dev gates' ; grep -nP '\x{2014}' docs/superpowers/specs/2026-09-17-tinkero-design.md docs/guides/phase-2f-vm-check.md | head` and compare the em-dash hits with `git diff -U0 | grep -P '^\+.*\x{2014}'` (the latter must print nothing: no new em dash).
Expected: gates all PASS; no added line carries an em dash.

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/specs/2026-09-17-tinkero-design.md docs/guides/phase-2f-vm-check.md
git commit -m "docs: spec 4.8 and the 2F VM guide describe the account-phase reset (#46)"
```

---

### Task 5: Final review, PR (orchestrator)

- [ ] Run the full verification once more on the final tree, as root in the image: `./dev check` (with `TINKERO_PAM_REAL=1`), `./dev gates`, and `shellcheck` on the CI list.
- [ ] Review the whole diff `git diff origin/master...HEAD` against issue #46, D1 to D7 and the Review Focus list.
- [ ] Commit this plan file (`docs/superpowers/plans/2026-09-28-issue-46-lock-pam-account-phase.md`) plus any review fixes. Task 1's commit carries `Closes #46`; the operator squash-merges.
- [ ] Run the whole of `.github/workflows/ci.yml` locally before any push: every step, in order, in a fresh `fedora:44` container as root with the workflow's own `dnf` line and `TINKERO_PAM_REAL=1` (ShellCheck list, `./dev check`, `./dev gates`, tinkero spec render/parse/rpmlint, package specs parse/rpmlint, the glaze, ttfx, quickshell-patch and tinkero SRPM steps, `rpmbuild --rebuild` plus `ci/check-rpm` plus `./dev gates-at`). Push only if every step passes; put the per-step results in the PR body.
- [ ] `git push -u origin task/e400a080`, then `gh pr create --base master` with a body that has "Closes #46", the root cause, the design decision, the real-PAM evidence, the D5 COPR note, the #37 checklist, the D6 note, and the manual Quickshell compile result from Task 3.
