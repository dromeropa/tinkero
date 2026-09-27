# Issue #30: the session-end sweep of `DCONF_PROFILE` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** after a Tinkero session ends, no running user service still carries `DCONF_PROFILE=tinkero`, so a GNOME login that reuses the user manager (lingering, or the ten-second window) never talks to a service reading or writing the Tinkero dconf database.

**Architecture:** a new oneshot user unit, `tinkero-session-end.service`, pulled in by a drop-in on uwsm's `wayland-session-shutdown.target` and ordered after it, runs `/usr/bin/tinkero-session-end`. The command does nothing while `graphical-session.target` is active. Once the session has ended, it unsets `DCONF_PROFILE` from the manager if the value is still `tinkero`, then restarts every running user service whose main process environment has `DCONF_PROFILE=tinkero` (stopping the transient D-Bus ones instead, which D-Bus activates again on demand), all with the clean environment.

**Tech Stack:** bash (`set -euo pipefail`, ShellCheck clean), systemd user units, the repo's TAP-style `tests/lib.sh`.

**Spec:** issue #30 (body; the thread has no comments), `docs/superpowers/specs/2026-09-17-tinkero-design.md` 4.9, `docs/superpowers/specs/2026-09-24-phase-2f-session-design.md` section 3 and D4, `docs/guides/phase-2f-vm-check.md` section 4.

## The design decision

Issue #30 leaves a fork open: stop the affected services at session end, or keep `DCONF_PROFILE` out of the activation environment and set it per process.

**Rejected: per process.** Under uwsm, applications launched with `uwsm app` (every Omarchy launcher) run as units of the user manager and get the activation environment, not Hyprland's. So do D-Bus-activated services such as `xdg-desktop-portal-gtk`, which reads `color-scheme` and friends from gsettings. Upstream's `autostart.lua` also pushes the compositor's whole environment into the manager (`systemctl --user import-environment`, `dbus-update-activation-environment --systemd --all`). Keeping the variable out of the activation environment would therefore send the portal, and every app launched through uwsm, back to GNOME's `~/.config/dconf/user`. That is the leak spec 4.9 exists to prevent, and it would weaken the isolation invariant.

**Chosen: stop the services after the session ends, and only then.** The failure mode is a process that inherited the variable during the session and outlived it. The fix is to end those processes once nothing can hand the variable out again. Four details decide where and how:

1. **Not the inhibitor's `ExecStopPost=`.** It also fires mid-session: `Restart=on-failure` runs `ExecStopPost` between restarts, and so does a manual restart. Stopping `pipewire-pulse` there would cut audio in a live session. It also runs *before* uwsm's `cleanup-env`: the inhibitor is `After=graphical-session.target`, so it stops before the target, while `wayland-wm-env@.service`, whose `ExecStopPost=uwsm aux cleanup-env` unsets the variable, stops after `graphical-session-pre.target`. A service stopped at that point could be D-Bus-activated again by a Tinkero client still exiting and pick the variable up again. D4's original one-liner (`ExecStopPost=systemctl --user unset-environment DCONF_PROFILE`) does not work for the reason the issue gives: the manager's copy is already gone, and the live processes keep their inherited one.
2. **After uwsm's cleanup: `wayland-session-shutdown.target`.** In uwsm 0.26.5 (our COPR pin; unchanged on uwsm's master), `wayland-wm-env@.service` has `OnSuccess=` and `OnFailure=wayland-session-shutdown.target` and is `Conflicts=` + `Before=` that target. Starting the target therefore waits until the env unit has stopped, `ExecStopPost=cleanup-env` included. The target is also `After=` and `Conflicts=` `graphical-session.target`, `graphical-session-pre.target` and `xdg-desktop-autostart.target`, so it only becomes active once the whole graphical session is down. It is started on every session end (the env unit stops on all three: menu logout, `loginctl terminate-session`, a killed compositor) and never at session start. The man page documents it (`uwsm(1)`: "conflicts with targets above for shutdown"). A drop-in `wayland-session-shutdown.target.d/tinkero.conf` with `Wants=tinkero-session-end.service`, and `After=wayland-session-shutdown.target` in our unit, run the sweep at exactly that point. No `[Install]`, nothing is enabled, and `ci/gate-session-units` stays unchanged.
3. **dbus-broker has no separate activation environment.** `dbus-broker-launch` forwards `UpdateActivationEnvironment` to systemd's `SetEnvironment` (`src/launch/launcher.c`), and uwsm relies on that too: with dbus-broker it only unsets from the manager. After cleanup-env, the transient `dbus-:1.N-org.gnome.*@N.service` units that D-Bus starts next get a clean environment. (With classic dbus-daemon, uwsm writes empty values; Fedora 44 uses dbus-broker.)
4. **Restart, except what cannot be restarted (amended in the final review).** Once the manager's environment is clean, a restart gives the service a clean copy and keeps running whatever was running, which matters for a user's own long-running service that is not activatable (restarted from a terminal during the session, say): a stop would leave it down under lingering. `dconf.service` and `pipewire-pulse.service` are restarted. D-Bus's transient `dbus-:1.N-*@N.service` units (`Transient=yes`) cannot be restarted, so they are stopped, and D-Bus activates the name again, clean, on first use (GNOME Identity, Online Accounts, at-spi). The match is exact on `DCONF_PROFILE=tinkero`, so a user's own `DCONF_PROFILE` is never touched.

Safety rails in the command: it exits without doing anything while `graphical-session.target` is active (a manual `systemctl --user start tinkero-session-end.service` mid-session is a no-op). It never stops `dbus.service` or `dbus-broker.service`, because the user bus outliving the session is required, not a leak. It never stops its own unit. A failing stop is logged and the sweep goes on, and the command always exits 0 so session teardown never shows a failed unit. As belt and braces for a missed cleanup (for example a manager that already had the variable before the session, which uwsm then "restores" instead of unsetting), it unsets `DCONF_PROFILE` from the manager first when the value is `tinkero`.

## Global Constraints

- bash with `set -euo pipefail`, ShellCheck clean (`shellcheck -x -e SC1090,SC1091`, as CI runs it).
- No em dashes in Tinkero's own prose (code comments, docs, messages).
- Tests never touch the network or a real package manager, and never a real systemd: `systemctl` is a stub on PATH.
- Allowlists under `ci/allow/` only shrink; none should change.
- Do not add an `[Install]` section to any unit (`ci/gate-session-units`).
- Commit to the current branch `task/a614c364`; do not create or switch branches; never push `master`.

## Review Focus

1. A mid-session trigger (inhibitor crash-restart, manual start of the sweep): nothing is stopped and the manager's env is untouched. Test: target active -> no `stop`, no `unset-environment`.
2. A user who set their own `DCONF_PROFILE` (value not `tinkero`): their services and manager env are left alone. Test: `DCONF_PROFILE=user` service not stopped; manager `DCONF_PROFILE=custom` not unset.
3. Near-miss environ entries (`DCONF_PROFILE=tinkero2`, `XDCONF_PROFILE=tinkero`) are not matches. Test.
4. The user bus carrying the variable (dbus-broker restarted mid-session) is never stopped. Test: `dbus.service` / `dbus-broker.service` skipped.
5. A stop that fails, a PID that vanished (no environ), `MainPID=0`: the sweep continues and exits 0. Test.

---

### Task 1: the sweep command, its unit, its drop-in, tests (sonnet)

**Files:**
- Create: `bin/tinkero-session-end` (mode 0755)
- Create: `systemd/tinkero-session-end.service`
- Create: `systemd/wayland-session-shutdown.target.d/tinkero.conf`
- Create: `tests/test-session-end.sh`
- Modify: `tests/test-assemble.sh` (fixture root gains the two unit files; assert they land)
- Modify: `build/assemble` header comment (lines ~20-23) only if it enumerates `systemd/**` contents (it says "Tinkero's own session units and drop-ins", so likely no change)

**Interfaces:**
- Produces: `/usr/bin/tinkero-session-end` (no args; env `TINKERO_PROC` overrides `/proc` for tests); unit `tinkero-session-end.service`; drop-in path `usr/lib/systemd/user/wayland-session-shutdown.target.d/tinkero.conf`. Task 2's docs name these exactly.

- [ ] **Step 1: Write the failing test** `tests/test-session-end.sh`:

```bash
#!/bin/bash
# bin/tinkero-session-end against a stub systemctl and a fixture /proc (issue #30). The stub
# reads its world from files under $W and logs every call to $LOG; no real systemd is touched.
source "$(dirname "$0")/lib.sh"
d=$(mktmp); mkdir -p "$d/bin" "$d/proc"; export LOG=$d/log W=$d/world TINKERO_PROC=$d/proc
T=$ROOT/bin/tinkero-session-end
mkdir -p "$W"
cat > "$d/bin/systemctl" <<'S'
#!/bin/bash
echo "systemctl $*" >> "$LOG"
[[ $1 == --user ]] && shift
case $1 in
  is-active) [[ -f $W/active ]] ;;
  show-environment) cat "$W/env" 2>/dev/null || true ;;
  unset-environment) exit 0 ;;
  list-units) cat "$W/units" 2>/dev/null || true ;;
  show) u=${*: -1}; cat "$W/pid.$u" 2>/dev/null || echo 0 ;;
  stop) u=${*: -1}; [[ -f $W/fail.$u ]] && exit 1; exit 0 ;;
esac
S
chmod +x "$d/bin/systemctl"; export PATH=$d/bin:$PATH

# svc NAME PID ENV...: a running service whose main process has the given environment
svc() {
  local name=$1 pid=$2; shift 2
  printf '%s loaded active running x\n' "$name" >> "$W/units"
  echo "$pid" > "$W/pid.$name"
  if [[ $pid != 0 ]]; then mkdir -p "$TINKERO_PROC/$pid"; printf '%s\0' "$@" > "$TINKERO_PROC/$pid/environ"; fi
}
reset() { rm -rf "$W" "$TINKERO_PROC" "$LOG"; mkdir -p "$W" "$TINKERO_PROC"; : > "$LOG"; }

# 1. A live session: nothing is stopped or unset, whatever the services carry.
reset; : > "$W/active"; echo DCONF_PROFILE=tinkero > "$W/env"
svc dconf.service 101 HOME=/h DCONF_PROFILE=tinkero
out=$("$T" 2>&1); rc=$?
assert_eq "$rc" 0 "live session: exits 0"
assert_contains "$out" "graphical session is active" "live session: says why it does nothing"
assert_eq "$(grep -c ' stop \| unset-environment ' "$LOG")" 0 "live session: nothing stopped or unset"

# 2. Ended session: only exact DCONF_PROFILE=tinkero main processes are stopped.
reset
svc dconf.service 101 HOME=/h DCONF_PROFILE=tinkero
svc pipewire-pulse.service 102 DCONF_PROFILE=tinkero LANG=C
svc 'dbus-:1.2-org.gnome.Identity@0.service' 103 DCONF_PROFILE=tinkero
svc own-profile.service 104 DCONF_PROFILE=user
svc near-miss.service 105 DCONF_PROFILE=tinkero2 XDCONF_PROFILE=tinkero
svc clean.service 106 HOME=/h
svc no-main-pid.service 0
svc vanished.service 107; rm -rf "$TINKERO_PROC/107"
out=$("$T" 2>&1); rc=$?
assert_eq "$rc" 0 "ended: exits 0"
for u in dconf.service pipewire-pulse.service 'dbus-:1.2-org.gnome.Identity@0.service'; do
  assert_contains "$(cat "$LOG")" "stop $u" "ended: stops $u"
done
for u in own-profile.service near-miss.service clean.service no-main-pid.service vanished.service; do
  assert_eq "$(grep -cF "stop $u" "$LOG")" 0 "ended: leaves $u alone"
done
assert_contains "$out" "stopping dconf.service" "ended: names each service it stops"
assert_eq "$(grep -c 'unset-environment' "$LOG")" 0 "ended: manager already clean, nothing unset"

# 3. The manager still has DCONF_PROFILE=tinkero: unset first, before any stop.
reset; printf 'HOME=/h\nDCONF_PROFILE=tinkero\n' > "$W/env"
svc dconf.service 101 DCONF_PROFILE=tinkero
"$T" >/dev/null 2>&1
assert_contains "$(cat "$LOG")" "systemctl --user unset-environment DCONF_PROFILE" "leftover: unsets the manager's copy"
first_unset=$(grep -n 'unset-environment' "$LOG" | head -1 | cut -d: -f1)
first_stop=$(grep -n ' stop ' "$LOG" | head -1 | cut -d: -f1)
if (( first_unset < first_stop )); then ok "leftover: unset comes before the stops"; else not_ok "leftover: unset comes before the stops" "$(cat "$LOG")"; fi

# 4. A user's own DCONF_PROFILE in the manager is not ours to remove.
reset; echo DCONF_PROFILE=custom > "$W/env"
"$T" >/dev/null 2>&1
assert_eq "$(grep -c 'unset-environment' "$LOG")" 0 "own profile: manager env left alone"

# 5. The user bus and the sweep itself are never stopped; a failed stop does not end the sweep.
reset
svc dbus-broker.service 201 DCONF_PROFILE=tinkero
svc dbus.service 202 DCONF_PROFILE=tinkero
svc tinkero-session-end.service 203 DCONF_PROFILE=tinkero
svc a-fails.service 204 DCONF_PROFILE=tinkero; : > "$W/fail.a-fails.service"
svc b-after.service 205 DCONF_PROFILE=tinkero
out=$("$T" 2>&1); rc=$?
assert_eq "$rc" 0 "safety: exits 0 even when a stop fails"
for u in dbus-broker.service dbus.service tinkero-session-end.service; do
  assert_eq "$(grep -cF "stop $u" "$LOG")" 0 "safety: never stops $u"
done
assert_contains "$out" "a-fails.service" "safety: a failed stop is reported"
assert_contains "$(cat "$LOG")" "stop b-after.service" "safety: the sweep goes on after a failed stop"

# 6. The units: session-end only, after uwsm's env cleanup, nothing enabled.
u=$ROOT/systemd/tinkero-session-end.service; di=$ROOT/systemd/wayland-session-shutdown.target.d/tinkero.conf
assert_file "$u" "the sweep unit exists"
assert_file "$di" "the shutdown-target drop-in exists"
assert_eq "$(grep -cx 'Type=oneshot' "$u")" 1 "unit: a plain oneshot"
assert_eq "$(grep -c '^RemainAfterExit=' "$u")" 0 "unit: does not remain active, so it runs at every session end"
assert_eq "$(grep -cx 'After=wayland-session-shutdown.target' "$u")" 1 "unit: ordered after the shutdown target"
assert_eq "$(grep -cx 'ExecStart=/usr/bin/tinkero-session-end' "$u")" 1 "unit: runs the command"
assert_eq "$(grep -c '\[Install\]' "$u" "$di" | awk -F: '{s+=$2} END {print s}')" 0 "no [Install] in either file"
assert_eq "$(grep -cx 'Wants=tinkero-session-end.service' "$di")" 1 "drop-in: the shutdown target wants the sweep"
rm -rf "$d"; finish
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/test-session-end.sh`
Expected: `not ok` lines (command and units missing), non-zero exit.

- [ ] **Step 3: Implement** `bin/tinkero-session-end` (chmod 0755):

```bash
#!/bin/bash
# tinkero-session-end: after a Tinkero session has ended, stop the user services that were
# started during it and still carry DCONF_PROFILE=tinkero (issue #30, design spec 4.9). With
# lingering, the user manager outlives the session; a service D-Bus- or socket-activated inside
# it keeps the Tinkero dconf profile, and a later GNOME login would talk to it. Stopped here, it
# is activated again on first use with the manager's clean environment.
# Run by tinkero-session-end.service, which uwsm's wayland-session-shutdown.target wants: that
# target becomes active only after uwsm's cleanup-env has unset the session's variables.
set -euo pipefail
proc=${TINKERO_PROC:-/proc}
say() { echo "tinkero-session-end: $*"; }

# A live session is never touched, whatever started this.
if systemctl --user is-active --quiet graphical-session.target; then
  say "graphical session is active; nothing to do"
  exit 0
fi

# Belt and braces for uwsm's cleanup: nothing started from here on may inherit the profile.
if systemctl --user show-environment | grep -qx 'DCONF_PROFILE=tinkero'; then
  say "the user manager still has DCONF_PROFILE=tinkero; unsetting it"
  systemctl --user unset-environment DCONF_PROFILE || say "could not unset DCONF_PROFILE"
fi

while read -r unit _; do
  case $unit in
    # The user bus outlives every session by design; this unit is the sweep itself.
    dbus.service | dbus-broker.service | tinkero-session-end.service) continue ;;
  esac
  pid=$(systemctl --user show -p MainPID --value "$unit" 2>/dev/null || echo 0)
  [[ $pid =~ ^[0-9]+$ && $pid -gt 0 ]] || continue
  [[ -r $proc/$pid/environ ]] || continue
  grep -qxz 'DCONF_PROFILE=tinkero' "$proc/$pid/environ" 2>/dev/null || continue
  say "stopping $unit (started in the Tinkero session, still on its dconf profile)"
  systemctl --user stop "$unit" || say "could not stop $unit"
done < <(systemctl --user list-units --type=service --state=running --no-legend --plain)
exit 0
```

Note: `grep -z` reads the NUL-separated environ directly; a `tr | grep -q` pipeline under `pipefail` could report `tr`'s SIGPIPE on a long environ and skip a real match.

`systemd/tinkero-session-end.service`:

```ini
[Unit]
Description=Tinkero: stop user services still on the session's dconf profile after it ends
# uwsm starts wayland-session-shutdown.target at every session end, and only once its
# cleanup-env has unset the session's variables; Tinkero's drop-in on the target wants this unit.
# A service left running with DCONF_PROFILE=tinkero would serve a later GNOME login from the
# Tinkero dconf database (issue #30, spec 4.9).
After=wayland-session-shutdown.target

[Service]
Type=oneshot
ExecStart=/usr/bin/tinkero-session-end
TimeoutStartSec=60
```

`systemd/wayland-session-shutdown.target.d/tinkero.conf`:

```ini
# Tinkero: sweep the user services that still carry the session's DCONF_PROFILE once the
# session has ended and uwsm has cleaned up its environment (issue #30, spec 4.9).
[Unit]
Wants=tinkero-session-end.service
```

- [ ] **Step 4: Assembly coverage.** In `tests/test-assemble.sh`, next to the fixture lines that create `$r/systemd/...` (lines ~6-13): create `$r/systemd/wayland-session-shutdown.target.d/` and write minimal fixture copies of both new files; next to the `assert_file` lines ~77-80 add:

```bash
assert_file "$d/dest/usr/lib/systemd/user/tinkero-session-end.service" "Tinkero's session-end sweep unit lands"
assert_file "$d/dest/usr/lib/systemd/user/wayland-session-shutdown.target.d/tinkero.conf" "Tinkero's shutdown-target drop-in lands"
assert_file "$d/dest/usr/bin/tinkero-session-end" "the sweep command lands in /usr/bin"
```

(Check how the fixture root gets `bin/tinkero-*`: if the fixture root copies the real `bin/`, the command lands; otherwise add a fixture stub there, or drop the third assertion and instead assert it in the real-payload check of Step 6.)

- [ ] **Step 5: Run the tests**

Run: `bash tests/test-session-end.sh && bash tests/test-assemble.sh && bash tests/test-gates.sh`
Expected: all `ok`, final `1..N`, exit 0.

- [ ] **Step 6: Lint, full suite and gates in the pinned container**

Run (from the worktree): `podman run --rm -v "$PWD:/w:Z" -w /w localhost/tinkero-ci:44 bash -c 'shellcheck -x -e SC1090,SC1091 bin/tinkero-* tests/test-session-end.sh tests/test-assemble.sh && ./dev check && ./dev gates'`
Expected: no ShellCheck output; `./dev check` exit 0; `./dev gates` six `PASS` lines (session units: `7 listed, 9 unit files`; the sweep is not a session-start unit, so the list does not change).

- [ ] **Step 7: Commit**

```bash
git add bin/tinkero-session-end systemd/tinkero-session-end.service systemd/wayland-session-shutdown.target.d/tinkero.conf tests/test-session-end.sh tests/test-assemble.sh
git commit -m "Stop user services still on DCONF_PROFILE=tinkero after the session ends (#30)"
```

### Task 2: docs (haiku)

**Files:**
- Modify: `docs/superpowers/specs/2026-09-24-phase-2f-session-design.md` section 3 (last-but-one paragraph, "uwsm removes the variables...") and D4
- Modify: `docs/superpowers/specs/2026-09-17-tinkero-design.md` 4.9, the dconf bullet's "Two known limits" sentence, and the 4.2 `%install` item 6 unit list
- Modify: `docs/guides/phase-2f-vm-check.md` section 4 (after the checkbox list's fourth box, and the "If `user env` shows..." paragraph)

**Interfaces:**
- Consumes: names from Task 1: `tinkero-session-end.service`, `/usr/bin/tinkero-session-end`, `wayland-session-shutdown.target.d/tinkero.conf`.

- [ ] **Step 1: Design 2F section 3.** Replace the sentence starting `If it fails, the fallback is one more line in the inhibitor unit,` through the end of that paragraph with:

`The 2F VM check (#27, issue #30) found the cleanup works but is not enough: user services D-Bus- or socket-activated during the session (dconf.service, pipewire-pulse, at-spi, GNOME Online Accounts) keep the variable in their own environment and outlive the session. The one-line fallback first written here, \`ExecStopPost=/usr/bin/systemctl --user unset-environment DCONF_PROFILE\` in the inhibitor unit, cannot fix that (the manager's copy is already gone; the processes keep theirs), and the inhibitor's \`ExecStopPost\` also fires on a mid-session restart and before uwsm's cleanup. Instead \`tinkero-session-end.service\`, wanted by a drop-in on uwsm's \`wayland-session-shutdown.target\` and ordered after it, runs \`tinkero-session-end\` once the session is down and the environment clean: it stops every running user service whose main process still has \`DCONF_PROFILE=tinkero\` (never the user bus), and D-Bus or socket activation brings each back, clean, on first use. Setting the variable per process instead was rejected: apps launched through \`uwsm app\` and D-Bus-activated portals get the activation environment, so they would read GNOME's database.`

- [ ] **Step 2: D4 in section 8.** Replace `Isolation after the session ends relies on uwsm's own cleanup of the activation environment; the VM check tests it and section 3 names the one-line fallback.` with `Isolation after the session ends relies on uwsm's own cleanup of the activation environment plus \`tinkero-session-end\`, which stops the user services that inherited the variable (issue #30, section 3).`

- [ ] **Step 3: Master spec 4.9.** In the dconf bullet, replace `and a user service that was already running with GNOME's environment (only possible without a full logout in between) keeps reading GNOME's database until it restarts.` with `and a user service that was already running with GNOME's environment (only possible without a full logout in between) keeps reading GNOME's database until it restarts. The reverse direction is closed: a user service started during the Tinkero session inherits \`DCONF_PROFILE=tinkero\`, so at every session end, once uwsm has cleaned the environment, \`tinkero-session-end.service\` (wanted by a drop-in on uwsm's \`wayland-session-shutdown.target\`) stops each one still carrying it, and activation brings it back clean (issue #30).` In 4.2 `%install` item 6, after `and \`tinkero-inhibit-power-key.service\`` insert `, \`tinkero-session-end.service\` with its drop-in on \`wayland-session-shutdown.target\``.

- [ ] **Step 4: VM guide section 4.** After the fourth checkbox add:

`- [ ] after each cycle, \`journalctl --user -b -u tinkero-session-end.service\` shows a run at that session end naming the services it stopped (issue #30), and no \`stopping\` line from inside a live session`

In the paragraph beginning `If \`user env\` shows`, append: `A service under the \`DCONF_PROFILE\` heading with \`user env\` at \`none\` means the session-end sweep did not run or missed it (issue #30): record the unit and that journal.`

- [ ] **Step 5: Check.** Run `grep -nP '\x{2014}' <the three files>` restricted to the added lines (`git diff -U0 | grep '^+' | grep -P '\x{2014}'`): expect no output. Run `./dev check` (as in Task 1 Step 6): green.

- [ ] **Step 6: Commit**

```bash
git add docs/
git commit -m "Docs: the session-end DCONF_PROFILE sweep replaces D4's unset fallback (#30)"
```

## What only a real VM can verify (the #37 re-run)

The unit ordering against uwsm (the sweep runs after cleanup-env on all three session ends), that the stopped services come back clean under GNOME, that no audio or a11y is disrupted inside a live session, and the guide's section 4 heading being empty in every GNOME snapshot.
