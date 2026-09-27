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
  show) u=${*: -1}
    case $3 in
      MainPID) cat "$W/pid.$u" 2>/dev/null || echo 0 ;;
      Transient) if [[ -f $W/transient.$u ]]; then echo yes; else echo no; fi ;;
    esac ;;
  stop|restart) u=${*: -1}; [[ -f $W/fail.$u ]] && exit 1; exit 0 ;;
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
# touched NAME: how many stop or restart calls the stub logged for NAME
touched() { grep -cF -e "stop $1" -e "restart $1" "$LOG"; }
reset() { rm -rf "$W" "$TINKERO_PROC" "$LOG"; mkdir -p "$W" "$TINKERO_PROC"; : > "$LOG"; }

# 1. A live session: nothing is stopped, restarted or unset, whatever the services carry.
reset; : > "$W/active"; echo DCONF_PROFILE=tinkero > "$W/env"
svc dconf.service 101 HOME=/h DCONF_PROFILE=tinkero
out=$("$T" 2>&1); rc=$?
assert_eq "$rc" 0 "live session: exits 0"
assert_contains "$out" "graphical session is active" "live session: says why it does nothing"
assert_eq "$(grep -c ' stop \| restart \| unset-environment ' "$LOG")" 0 "live session: nothing stopped, restarted or unset"

# 2. Ended session: only exact DCONF_PROFILE=tinkero main processes are touched: D-Bus's
# transient units are stopped (they cannot be restarted), every other one restarted so a user's
# own long-running service is not left down.
reset
svc dconf.service 101 HOME=/h DCONF_PROFILE=tinkero
svc pipewire-pulse.service 102 DCONF_PROFILE=tinkero LANG=C
svc 'dbus-:1.2-org.gnome.Identity@0.service' 103 DCONF_PROFILE=tinkero; : > "$W/transient.dbus-:1.2-org.gnome.Identity@0.service"
svc own-profile.service 104 DCONF_PROFILE=user
svc near-miss.service 105 DCONF_PROFILE=tinkero2 XDCONF_PROFILE=tinkero
svc clean.service 106 HOME=/h
svc no-main-pid.service 0
svc vanished.service 107; rm -rf "$TINKERO_PROC/107"
out=$("$T" 2>&1); rc=$?
assert_eq "$rc" 0 "ended: exits 0"
for u in dconf.service pipewire-pulse.service; do
  assert_contains "$(cat "$LOG")" "systemctl --user restart $u" "ended: restarts $u"
  assert_eq "$(grep -cF "systemctl --user stop $u" "$LOG")" 0 "ended: does not stop $u"
done
u='dbus-:1.2-org.gnome.Identity@0.service'
assert_contains "$(cat "$LOG")" "systemctl --user stop $u" "ended: stops the transient $u"
assert_eq "$(grep -cF "systemctl --user restart $u" "$LOG")" 0 "ended: does not restart the transient $u"
for u in own-profile.service near-miss.service clean.service no-main-pid.service vanished.service; do
  assert_eq "$(touched "$u")" 0 "ended: leaves $u alone"
done
assert_contains "$out" "restarting dconf.service" "ended: names each service it restarts"
assert_contains "$out" "stopping dbus-:1.2-org.gnome.Identity@0.service" "ended: names each service it stops"
assert_eq "$(grep -c 'unset-environment' "$LOG")" 0 "ended: manager already clean, nothing unset"

# 3. The manager still has DCONF_PROFILE=tinkero: unset first, before any restart.
reset; printf 'HOME=/h\nDCONF_PROFILE=tinkero\n' > "$W/env"
svc dconf.service 101 DCONF_PROFILE=tinkero
"$T" >/dev/null 2>&1
assert_contains "$(cat "$LOG")" "systemctl --user unset-environment DCONF_PROFILE" "leftover: unsets the manager's copy"
first_unset=$(grep -n 'unset-environment' "$LOG" | head -1 | cut -d: -f1)
first_restart=$(grep -n ' restart ' "$LOG" | head -1 | cut -d: -f1)
if (( ${first_unset:-0} > 0 && ${first_unset:-0} < ${first_restart:-0} )); then ok "leftover: unset comes before the restarts"; else not_ok "leftover: unset comes before the restarts" "$(cat "$LOG")"; fi

# 4. A user's own DCONF_PROFILE in the manager is not ours to remove.
reset; echo DCONF_PROFILE=custom > "$W/env"
"$T" >/dev/null 2>&1
assert_eq "$(grep -c 'unset-environment' "$LOG")" 0 "own profile: manager env left alone"

# 5. The user bus and the sweep itself are never touched; a failed restart does not end the sweep.
reset
svc dbus-broker.service 201 DCONF_PROFILE=tinkero
svc dbus.service 202 DCONF_PROFILE=tinkero
svc tinkero-session-end.service 203 DCONF_PROFILE=tinkero
svc a-fails.service 204 DCONF_PROFILE=tinkero; : > "$W/fail.a-fails.service"
svc b-after.service 205 DCONF_PROFILE=tinkero
out=$("$T" 2>&1); rc=$?
assert_eq "$rc" 0 "safety: exits 0 even when a restart fails"
for u in dbus-broker.service dbus.service tinkero-session-end.service; do
  assert_eq "$(touched "$u")" 0 "safety: never stops or restarts $u"
done
assert_contains "$out" "could not restart a-fails.service" "safety: a failed restart is reported"
assert_contains "$(cat "$LOG")" "restart b-after.service" "safety: the sweep goes on after a failed restart"

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
