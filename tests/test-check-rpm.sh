#!/bin/bash
# ci/check-rpm against stub rpm and rpm2cpio: rpm answers the two queries from files the test
# writes, rpm2cpio prints a cpio archive the test builds from a fixture payload.
source "$(dirname "$0")/lib.sh"
d=$(mktmp); mkdir -p "$d/bin"
cat > "$d/bin/rpm" <<'S'
#!/bin/bash
case "$*" in
  *POSTTRANS*) cat "$POSTTRANS" ;;
  *FILEFLAGS*) cat "$FILES" ;;
  *) exit 1 ;;
esac
S
# shellcheck disable=SC2016  # $ARCHIVE belongs to the stub
printf '#!/bin/bash\ncat "$ARCHIVE"\n' > "$d/bin/rpm2cpio"
chmod +x "$d/bin"/*
export PATH=$d/bin:$PATH FILES=$d/files POSTTRANS=$d/posttrans ARCHIVE=$d/payload.cpio
: > "$d/tinkero.rpm"
good_files() {
  cat > "$FILES" <<'F'
g -rw-r--r-- root:root /etc/pam.d/omarchy-lock-password
g -rw-r--r-- root:root /etc/pam.d/omarchy-lock-fingerprint
 -rwxr-xr-x root:root /usr/bin/tinkero-pam-sync
F
  echo '/usr/bin/tinkero-pam-sync || echo "tinkero: tinkero-pam-sync failed" >&2' > "$POSTTRANS"
}
payload() {   # build the archive from a fixture payload; extra args are paths to leave out
  local p=$d/p skip
  rm -rf "$p"; mkdir -p "$p/usr/bin" "$p/usr/share/tinkero/pam" "$p/usr/share/uwsm/env.d"
  printf '#!/bin/bash\n' > "$p/usr/bin/tinkero-pam-sync"; chmod 755 "$p/usr/bin/tinkero-pam-sync"
  echo wrapped > "$p/usr/share/tinkero/pam/omarchy-lock-password.wrapped"
  echo plain > "$p/usr/share/tinkero/pam/omarchy-lock-password.plain"
  echo 'export DCONF_PROFILE=tinkero' > "$p/usr/share/uwsm/env.d/20-tinkero"
  for skip in "$@"; do rm -f "$p/$skip"; done
  ( cd "$p" && find . -mindepth 1 | cpio -o -H newc --quiet ) > "$ARCHIVE"
}
C=$ROOT/ci/check-rpm

good_files; payload
out=$("$C" "$d/tinkero.rpm" "$d/x1"); rc=$?
assert_eq "$rc" 0 "a good package passes"
assert_contains "$out" "PASS: rpm tinkero.rpm" "and says so"
assert_file "$d/x1/usr/share/uwsm/env.d/20-tinkero" "the payload is unpacked into DIR"

sed -i 's#^g -rw-r--r-- root:root /etc/pam.d/omarchy-lock-password#c -rw-r--r-- root:root /etc/pam.d/omarchy-lock-password#' "$FILES"
out=$("$C" "$d/tinkero.rpm" "$d/x2"); rc=$?
assert_eq "$rc" 1 "a PAM file that is not %ghost fails"
assert_contains "$out" "FAIL: /etc/pam.d/omarchy-lock-password: want 'g -rw-r--r-- root:root', got 'c -rw-r--r-- root:root'" "and names the flags"

good_files; sed -i '/omarchy-lock-fingerprint/d' "$FILES"
out=$("$C" "$d/tinkero.rpm" "$d/x3"); rc=$?
assert_eq "$rc" 1 "a missing fingerprint entry fails"
assert_contains "$out" "FAIL: /etc/pam.d/omarchy-lock-fingerprint is not in the package" "and names it"

good_files; sed -i 's#^g -rw-r--r-- root:root /etc/pam.d/omarchy-lock-fingerprint#g -rw------- root:root /etc/pam.d/omarchy-lock-fingerprint#' "$FILES"
out=$("$C" "$d/tinkero.rpm" "$d/x4"); rc=$?
assert_contains "$out" "FAIL: /etc/pam.d/omarchy-lock-fingerprint: want 'g -rw-r--r-- root:root', got 'g -rw------- root:root'" "a wrong mode fails"

good_files; echo '(none)' > "$POSTTRANS"
out=$("$C" "$d/tinkero.rpm" "$d/x5"); rc=$?
assert_eq "$rc" 1 "no %posttrans fails"
assert_contains "$out" "%posttrans does not run /usr/bin/tinkero-pam-sync" "and says so"

good_files; payload usr/share/uwsm/env.d/20-tinkero
out=$("$C" "$d/tinkero.rpm" "$d/x6"); rc=$?
assert_eq "$rc" 1 "a payload without the env file fails"
assert_contains "$out" "FAIL: payload lacks /usr/share/uwsm/env.d/20-tinkero" "and names it"

payload; mkdir -p "$d/p/etc/pam.d"; echo x > "$d/p/etc/pam.d/omarchy-lock-password"
( cd "$d/p" && find . -mindepth 1 | cpio -o -H newc --quiet ) > "$ARCHIVE"
out=$("$C" "$d/tinkero.rpm" "$d/x7"); rc=$?
assert_contains "$out" "FAIL: %ghost file /etc/pam.d/omarchy-lock-password has content in the payload" "a ghost file with content fails"

payload; mkdir -p "$d/x8"; echo x > "$d/x8/stale"
out=$("$C" "$d/tinkero.rpm" "$d/x8" 2>&1); rc=$?
assert_eq "$rc" 2 "a non-empty DIR is refused"
assert_contains "$out" "DIR must be empty" "and says so"
"$C" >/dev/null 2>&1; assert_eq "$?" 2 "no arguments print usage and exit 2"
rm -rf "$d"; finish
