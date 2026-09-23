#!/bin/bash
# bin/tinkero-provision against a fixture payload under a temporary HOME, with stub dconf,
# systemctl, git and the notification commands on PATH. No real home directory is touched.
source "$(dirname "$0")/lib.sh"
d=$(mktmp); pay=$("$ROOT/tests/fixtures/make-payload.sh" "$d/payload"); mkdir -p "$d/bin"; export LOG=$d/log
T=$ROOT/bin/tinkero-provision
for s in systemctl omarchy-notification-send omarchy-notification-wait omarchy-theme-set; do
  # shellcheck disable=SC2016  # the stubs log their own arguments at run time
  printf '#!/bin/bash\necho "%s $*" >> "$LOG"\n' "$s" > "$d/bin/$s"
done
cat > "$d/bin/dconf" <<'S'
#!/bin/bash
echo "dconf $* profile=${DCONF_PROFILE:-}" >> "$LOG"
case $1 in dump) printf '[org/gnome]\nk=1\n' ;; load) cat > "$DCONF_IN" ;; esac
S
printf '#!/bin/bash\nexit 1\n' > "$d/bin/git"     # no global identity configured
cat > "$d/bin/omarchy-default-agent" <<'S'
#!/bin/bash
printf '%s' "${AGENT:-}"
S
chmod +x "$d/bin"/*
export PATH=$d/bin:$PATH DCONF_IN=$d/dconf.in
export OMARCHY_PATH=$pay/usr/share/omarchy TINKERO_SHARE=$pay/usr/share/tinkero
export TINKERO_DCONF_PROFILE=$pay/etc/dconf/profile/tinkero TINKERO_UNIT_DIR=$pay/usr/lib/systemd/user
export TINKERO_EUID=1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent
unset HYPRLAND_INSTANCE_SIGNATURE XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME
newhome() { export HOME=$d/home$1; rm -rf "$HOME"; mkdir -p "$HOME"; : > "$LOG"; }
tsv() { grep -v '^#' "$HOME/.local/state/tinkero/seeded.tsv"; }
row() { tsv | awk -F'\t' -v p="$1" '$1 == p { print $2 "\t" $3 "\t" $4 }'; }
sha() { sha256sum "$1" | cut -d' ' -f1; }

# 1. The decision table (design 2E, section 2.3), one row per case; "link" is a symlinked target.
while read -r name src tgt row st want; do
  got=$(TINKERO_PROVISION_SOURCED=1 bash -c 'source "$1"; seed_decide "$2" "$3" "$4" "$5"' bash "$T" "$src" "$tgt" "$row" "$st")
  assert_eq "$got" "$want" "decide: $name"
done <<'TABLE'
new h - - - seed
have h x - - conflict
unchanged h h h seeded current
upstream-changed h2 h h seeded update
user-changed h u h seeded keep-user
both-changed h2 u h seeded moved
user-deleted h - h seeded mark-removed
user-deleted-earlier h - h removed-by-user skip-removed
user-recreated-same h h h removed-by-user current
user-recreated-other h u h removed-by-user keep-user
upstream-removed-unchanged - h h seeded delete
upstream-removed-changed - u h seeded orphan
gone-both - - h seeded drop-row
orphan-readded h u h orphaned keep-user
symlink-new h link - - conflict
symlink-tracked h link h seeded keep-user
symlink-upstream-gone - link h seeded orphan
TABLE

# 2. --plan on an empty home writes nothing and names every file
newhome 1
out=$("$T" --plan)
assert_eq "$(grep -c $'^seed\t' <<<"$out")" 12 "plan: twelve files to seed on an empty home"
assert_contains "$out" $'seed\t.config/hypr/bindings.lua' "plan: config files"
assert_contains "$out" $'seed\t.local/share/applications/Disk Usage.desktop' "plan: a launcher with a space in its name"
assert_contains "$out" $'seed\t.XCompose' "plan: the XCompose file upstream's leaf would write"
assert_contains "$out" $'seed\t.local/state/omarchy/preinstalls-removed' "plan: the preinstalls marker"
if grep -q chromium <<<"$out"; then not_ok "plan: skip list honoured"; else ok "plan: skip list honoured"; fi
if grep -q -i 'youtube\|hey' <<<"$out"; then not_ok "plan: web-app launchers are not seeded"; else ok "plan: web-app launchers are not seeded"; fi
assert_contains "$out" $'step\tdconf:' "plan: lists the steps"
assert_eq "$(find "$HOME" -mindepth 1 | wc -l)" 0 "plan: the home is still empty"

# 3. A full run seeds, records, and is idempotent
echo 'echo mine' > "$HOME/.bashrc"
out=$("$T" --yes 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 0 "provision: exit 0"
assert_eq "$(cat "$HOME/.config/hypr/bindings.lua")" "-- tinkero bindings: tmux and herdr" "provision: Tinkero's override wins over upstream's file"
assert_file "$HOME/.config/omarchy/branding/about.txt" "provision: branding seeded"
assert_file "$HOME/.local/share/applications/Disk Usage.desktop" "provision: launcher seeded"
assert_no_path "$HOME/.local/share/applications/YouTube.desktop" "provision: web-app launcher not seeded"
assert_no_path "$HOME/.config/chromium" "provision: skip list honoured"
assert_file "$HOME/.local/state/omarchy/preinstalls-removed" "provision: preinstalls marker"
assert_eq "$(sed -n 2p "$HOME/.XCompose")" '<Multi_key> <space> <n> : ""' "provision: XCompose from upstream's leaf, no identity"
assert_eq "$(tsv | wc -l)" 12 "provision: twelve rows recorded"
assert_eq "$(row .config/hypr/hyprland.lua)" "$(sha "$HOME/.config/hypr/hyprland.lua")"$'\tv4.0.4-1\tseeded' "provision: a row is sha256, release, state"
assert_eq "$(row '.local/share/applications/Disk Usage.desktop' | cut -f3)" seeded "provision: the row with a space in its path"
assert_eq "$(grep -c 'tinkero-provision' "$HOME/.bashrc")" 1 "provision: the guarded bashrc line, once"
assert_eq "$(head -n1 "$HOME/.bashrc")" "echo mine" "provision: the user's bashrc content is kept"
assert_eq "$(cat "$HOME/.local/state/tinkero/release")" "v4.0.4-1" "provision: release recorded"
assert_contains "$out" "Note for v4.0.4" "provision: config notes shown"
assert_eq "$(stat -c %a "$HOME/.config/hypr/hyprland.lua")" 644 "provision: seeded files are 0644"
: > "$LOG"; out2=$("$T" --yes 2>&1)
assert_eq "$(grep -c $'^current\t' <<<"$("$T" --plan)")" 12 "re-run: everything is current"
assert_eq "$(grep -c 'tinkero-provision' "$HOME/.bashrc")" 1 "re-run: the bashrc line is not duplicated"
if grep -q "Note for" <<<"$out2"; then not_ok "re-run: notes are shown once"; else ok "re-run: notes are shown once"; fi

# 4. Never overwrite: a file the user already has is a conflict
newhome 2
mkdir -p "$HOME/.config/hypr"; echo 'mine' > "$HOME/.config/hypr/hyprland.lua"
mkdir -p "$HOME/.config/git"; ln -s /dev/null "$HOME/.config/git/config"
out=$("$T" --yes 2>&1)
assert_eq "$(cat "$HOME/.config/hypr/hyprland.lua")" "mine" "conflict: the user's file is untouched"
assert_contains "$out" "conflict: .config/hypr/hyprland.lua" "conflict: reported"
assert_contains "$out" "diff $OMARCHY_PATH/config/hypr/hyprland.lua $HOME/.config/hypr/hyprland.lua" "conflict: with a diff command"
assert_symlink "$HOME/.config/git/config" /dev/null "conflict: a symlinked target is never written through"
assert_eq "$(tsv | wc -l)" 10 "conflict: neither file is recorded"
assert_contains "$("$T" --plan)" $'conflict\t.config/git/config' "conflict: still reported by --plan"

# 5. The git rule: no git configuration at all, or none is seeded
newhome 3; echo '[user]' > "$HOME/.gitconfig"
out=$("$T" --plan)
if grep -q 'git/config' <<<"$out"; then not_ok "git: ~/.gitconfig present, aliases not offered"; else ok "git: ~/.gitconfig present, aliases not offered"; fi

# 6. A bump: the three-way decisions on a provisioned home
newhome 4; "$T" --yes >/dev/null 2>&1
echo '-- looknfeel v2' > "$OMARCHY_PATH/config/hypr/looknfeel.lua"          # upstream changed, user did not
echo '-- tinkero bindings v2' > "$TINKERO_SHARE/config/hypr/bindings.lua"    # both changed
echo '-- my bindings' > "$HOME/.config/hypr/bindings.lua"
rm "$HOME/.config/hypr/hyprland.lua"                                        # user deleted
rm "$OMARCHY_PATH/config/git/config"                                        # upstream removed, user unchanged
rm "$OMARCHY_PATH/applications/Disk Usage.desktop"                          # upstream removed, user changed
echo 'edited' >> "$HOME/.local/share/applications/Disk Usage.desktop"
sed -i 's/tinkero_rev=1/tinkero_rev=2/' "$TINKERO_SHARE/upstream.lock"
plan=$("$T" --plan)
assert_contains "$plan" $'update\t.config/hypr/looknfeel.lua' "bump: unchanged by the user and changed upstream is updated"
assert_contains "$plan" $'moved\t.config/hypr/bindings.lua' "bump: changed by both is a moved default"
assert_contains "$plan" $'mark-removed\t.config/hypr/hyprland.lua' "bump: deleted by the user is marked"
assert_contains "$plan" $'delete\t.config/git/config' "bump: removed upstream and unchanged here is deleted"
assert_contains "$plan" $'orphan\t.local/share/applications/Disk Usage.desktop' "bump: removed upstream and changed here is an orphan"
out=$("$T" --yes 2>&1)
assert_eq "$(cat "$HOME/.config/hypr/looknfeel.lua")" "-- looknfeel v2" "bump: updated"
assert_eq "$(row .config/hypr/looknfeel.lua | cut -f2)" "v4.0.4-2" "bump: the row carries the new release"
assert_eq "$(cat "$HOME/.config/hypr/bindings.lua")" "-- my bindings" "bump: the user's edit is kept"
assert_contains "$out" "moved default: .config/hypr/bindings.lua" "bump: the moved default is reported"
assert_no_path "$HOME/.config/hypr/hyprland.lua" "bump: the deleted file is not reseeded"
assert_eq "$(row .config/hypr/hyprland.lua | cut -f3)" removed-by-user "bump: and its row says so"
assert_no_path "$HOME/.config/git/config" "bump: the upstream-removed file is deleted"
assert_eq "$(row .config/git/config)" "" "bump: and its row is dropped"
assert_eq "$(row '.local/share/applications/Disk Usage.desktop' | cut -f3)" orphaned "bump: the orphan is kept and marked"
"$T" --yes >/dev/null 2>&1
assert_no_path "$HOME/.config/hypr/hyprland.lua" "bump: a further run still does not reseed a removed file"
assert_contains "$("$T" --plan)" $'skip-removed\t.config/hypr/hyprland.lua' "bump: --plan shows it as removed by the user"

# 7. --reset and --reset-all
"$ROOT/tests/fixtures/make-payload.sh" "$d/payload" >/dev/null   # restore the fixture sources
sed -i 's/tinkero_rev=1/tinkero_rev=2/' "$TINKERO_SHARE/upstream.lock"
"$T" --reset .config/hypr/hyprland.lua >/dev/null
assert_file "$HOME/.config/hypr/hyprland.lua" "reset: a removed file comes back"
assert_eq "$(row .config/hypr/hyprland.lua | cut -f3)" seeded "reset: and its mark is cleared"
out=$("$T" --reset .config/hypr/bindings.lua 2>&1)
assert_eq "$(cat "$HOME/.config/hypr/bindings.lua")" "-- tinkero bindings: tmux and herdr" "reset: the packaged default is restored"
bak=$(find "$HOME/.config/hypr" -name 'bindings.lua.bak.*' | head -n1)
assert_eq "$(cat "${bak:-/dev/null}")" "-- my bindings" "reset: the user's version is backed up with a timestamp"
assert_contains "$out" "backed up .config/hypr/bindings.lua" "reset: the backup is named"
"$T" --reset nope >/dev/null 2>&1 && rc=0 || rc=$?
assert_eq "$rc" 1 "reset: an unknown path fails"
echo x > "$HOME/.config/hypr/looknfeel.lua"; echo y > "$HOME/.local/state/tensaku/state.toml"
"$T" --reset-all >/dev/null
assert_eq "$(cat "$HOME/.config/hypr/looknfeel.lua")$(cat "$HOME/.local/state/tensaku/state.toml")" "-- looknfeel v1annotation-size-factor = 2.0" "reset-all: every packaged default restored"
assert_eq "$(grep -c $'^current\t' <<<"$("$T" --plan)")" 12 "reset-all: everything current afterwards"
sed -i 's/tinkero_rev=2/tinkero_rev=1/' "$TINKERO_SHARE/upstream.lock"

# 8. Refusals
TINKERO_EUID=0 "$T" --plan >/dev/null 2>&1 && rc=0 || rc=$?
assert_eq "$rc" 1 "refuses to run as root"
newhome 5; "$T" --yes >/dev/null 2>&1
echo 'broken line' >> "$HOME/.local/state/tinkero/seeded.tsv"
out=$("$T" --plan 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 1 "a malformed seeded.tsv stops the run"
assert_contains "$out" "seeded.tsv line 14" "and names the line"

# 8b. Robustness (review of plan 2E, Task 3)
# (1) a write failure mid apply_plan does not abort the run or lose already-written rows
newhome 11
mkdir -p "$HOME/.local/share"; : > "$HOME/.local/share/applications"
out=$("$T" --yes 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 1 "robustness: a write failure mid-apply exits 1"
assert_eq "$(tsv | wc -l)" 10 "robustness: only the files that could not be written are unrecorded"
assert_eq "$(row .config/hypr/hyprland.lua | cut -f3)" seeded "robustness: an unaffected file is still recorded"
assert_contains "$out" "not complete:" "robustness: reported as not complete"
assert_no_path "$HOME/.local/state/tinkero/release" "robustness: no release file when a file failed to write"
plan=$("$T" --plan)
assert_contains "$plan" $'current\t.config/hypr/hyprland.lua' "robustness: an unaffected file is current"
if grep -q $'conflict\t.config/hypr/hyprland.lua' <<<"$plan"; then not_ok "robustness: the unaffected file is not a conflict"; else ok "robustness: the unaffected file is not a conflict"; fi
rm "$HOME/.local/share/applications"
out=$("$T" --yes 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 0 "robustness: a further run succeeds once the obstruction is gone"
assert_eq "$(tsv | wc -l)" 12 "robustness: all twelve rows recorded once the obstruction is gone"

# (2) a directory at a target path is never written through or deleted
newhome 12
mkdir -p "$HOME/.config/hypr/looknfeel.lua"
"$T" --yes >/dev/null 2>&1 || true
if [[ -d "$HOME/.config/hypr/looknfeel.lua" ]]; then ok "robustness: the directory at a target path is untouched"; else not_ok "robustness: the directory at a target path is untouched"; fi
assert_eq "$(find "$HOME/.config/hypr/looknfeel.lua" -mindepth 1 | wc -l)" 0 "robustness: nothing was written into the directory"
assert_eq "$(tsv | wc -l)" 11 "robustness: the directory's row is not recorded"
plan=$("$T" --plan) && rc2=0 || rc2=$?
assert_eq "$rc2" 0 "robustness: --plan still succeeds with a directory at a target path"
assert_contains "$plan" $'conflict\t.config/hypr/looknfeel.lua' "robustness: the directory is reported as a conflict"
out2=$("$T" --reset .config/hypr/looknfeel.lua 2>&1)
assert_eq "$(find "$HOME/.config/hypr/looknfeel.lua" -mindepth 1 | wc -l)" 0 "robustness: --reset leaves the directory in place"
assert_contains "$out2" "not a regular file" "robustness: --reset explains why"

# (3) --reset-all does not die at the first symlinked target
newhome 13
"$T" --yes >/dev/null 2>&1
rm "$HOME/.config/hypr/hyprland.lua"; ln -s /dev/null "$HOME/.config/hypr/hyprland.lua"
echo x > "$HOME/.config/hypr/looknfeel.lua"
out=$("$T" --reset-all 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 0 "robustness: --reset-all succeeds even with a symlinked target"
assert_symlink "$HOME/.config/hypr/hyprland.lua" /dev/null "robustness: the symlink is left alone by --reset-all"
assert_eq "$(cat "$HOME/.config/hypr/looknfeel.lua")" "-- looknfeel v1" "robustness: other defaults are still restored"
assert_contains "$out" "is a symlink; not touching it" "robustness: the skip is reported"

# (4) a missing .bashrc is created with only the guarded line, no leading blank line
newhome 14
"$T" --yes >/dev/null 2>&1
assert_eq "$(wc -l < "$HOME/.bashrc")" 1 "robustness: a missing .bashrc gets exactly one line"
assert_eq "$(head -c1 "$HOME/.bashrc")" "[" "robustness: no leading blank line in a fresh .bashrc"

# (5) %q quoting is transparent for plain paths (regression for the existing diff-command test)
newhome 15
mkdir -p "$HOME/.config/hypr"; echo mine > "$HOME/.config/hypr/hyprland.lua"
out=$("$T" --yes 2>&1)
assert_contains "$out" "diff $OMARCHY_PATH/config/hypr/hyprland.lua $HOME/.config/hypr/hyprland.lua" "robustness: %q leaves plain paths unquoted in the diff command"

# 9. The upstream leaves run in order, headless outside a session, and one failure does not stop the rest
newhome 6
out=$("$T" --yes 2>&1)
assert_eq "$(grep -o '^leaf [a-z-]*' "$LOG" | paste -sd' ')" "leaf theme leaf mise-work leaf mise" "steps: skills, theme, mise-work, mise; nothing in-session"
assert_contains "$(cat "$LOG")" "leaf theme headless=1" "steps: the first theme is headless outside a session"
assert_symlink "$HOME/.claude/skills/omarchy" "$OMARCHY_PATH/default/agents/skills/omarchy" "steps: skills linked (claude)"
assert_symlink "$HOME/.hermes/skills/diagnose-crash" "$OMARCHY_PATH/default/agents/skills/diagnose-crash" "steps: skills linked (hermes)"
assert_contains "$(cat "$LOG")" "dconf dump / profile=user" "dconf: GNOME's settings are dumped from the user profile"
assert_contains "$(cat "$LOG")" "dconf load / profile=tinkero" "dconf: and loaded into the tinkero profile"
assert_eq "$(cat "$DCONF_IN")" $'[org/gnome]\nk=1' "dconf: the dump is what gets loaded"
assert_contains "$out" "step mise: ok" "steps: reported"
: > "$LOG"; "$T" --yes >/dev/null 2>&1
assert_eq "$(grep -c '^dconf' "$LOG")" 0 "dconf: seeded once"
assert_contains "$("$T" --plan)" $'step\tdconf: seed ~/.config/dconf/tinkero from the GNOME settings done' "plan: the dconf step shows done"
: > "$LOG"; "$T" --reset dconf >/dev/null 2>&1
assert_eq "$(grep -c '^dconf' "$LOG")" 2 "reset dconf: dumped and loaded again"
newhome 7
out=$(FAIL_MISE_WORK=1 "$T" --yes 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 1 "a failing leaf makes the run fail"
assert_contains "$out" "not complete: mise-work failed" "and names it"
assert_eq "$(grep -o '^leaf [a-z-]*' "$LOG" | paste -sd' ')" "leaf theme leaf mise-work leaf mise" "but the later leaves still ran"
assert_no_path "$HOME/.local/state/tinkero/release" "and the release is not recorded"
"$T" --yes >/dev/null 2>&1; assert_file "$HOME/.local/state/tinkero/release" "a later run completes and records it"
newhome 10
out=$(env -u DBUS_SESSION_BUS_ADDRESS "$T" --yes 2>&1)
assert_contains "$out" "dconf: no session bus" "dconf: no bus is a skip with the reason, not a failure"
assert_eq "$(grep -c '^dconf' "$LOG")" 0 "dconf: nothing ran without a bus"
assert_file "$HOME/.local/state/tinkero/release" "dconf: a skip does not stop provisioning"
: > "$LOG"; "$T" --session >/dev/null 2>&1
assert_contains "$(cat "$LOG")" "dconf load / profile=tinkero" "dconf: the next session start seeds it"

# 10. --session: provision when stale, in-session steps once, units, notices once
newhome 8
out=$("$T" --session 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 0 "session: a fresh home is provisioned"
assert_contains "$(cat "$LOG")" "leaf theme headless=0" "session: the first theme is applied for real inside the session"
assert_eq "$(grep -c '^leaf hardware' "$LOG")" 2 "session: the hardware fixes run"
assert_eq "$(grep -c '^leaf audio-tuning' "$LOG")" 1 "session: the speaker tuning runs"
assert_contains "$(cat "$LOG")" "systemctl --user start omarchy-keep.service" "session: listed units are started"
assert_contains "$out" "unit missing.service is not installed; skipped" "session: a missing unit is skipped and named"
assert_eq "$(grep -c '^omarchy-notification-send' "$LOG")" 2 "session: the welcome and the agent invitation"
assert_eq "$(grep -c '^omarchy-notification-wait' "$LOG")" 1 "session: after waiting for the notification service"
assert_eq "$(grep -c '^omarchy-theme-set' "$LOG")" 0 "session: no second theme application when the first was in-session"
assert_contains "$out" "bashrc: the guarded line is not in" "session: the bashrc line is never appended at session start"
: > "$LOG"; out=$("$T" --session 2>&1)
assert_eq "$(grep -c '^leaf' "$LOG")" 0 "session: current release, no leaves"
assert_contains "$(cat "$LOG")" "systemctl --user start omarchy-keep.service" "session: units are started every time"
assert_eq "$(grep -c '^omarchy-notification-send' "$LOG")" 0 "session: notices are sent once"
: > "$LOG"; "$T" --session --force >/dev/null 2>&1
assert_eq "$(grep -o '^leaf [a-z-]*' "$LOG" | paste -sd' ')" "leaf theme leaf mise-work leaf mise" "session --force: reprovisions, the once-only steps stay done"
newhome 9; AGENT=claude "$T" --session >/dev/null 2>&1
assert_eq "$(grep -c '^omarchy-notification-send' "$LOG")" 1 "session: no agent invitation when a default agent is set"
export HOME=$d/home6; : > "$LOG"   # provisioned outside a session above
mkdir -p "$HOME/.local/state/omarchy/current"; echo "Tokyo Night" > "$HOME/.local/state/omarchy/current/theme.name"
"$T" --session >/dev/null 2>&1
assert_contains "$(cat "$LOG")" "omarchy-theme-set Tokyo Night" "session: a theme set headless at install is applied once inside the session"
: > "$LOG"; "$T" --session >/dev/null 2>&1
assert_eq "$(grep -c '^omarchy-theme-set' "$LOG")" 0 "session: and only once"

# 11. --remove undoes what was written and keeps what the user changed
export HOME=$d/home8; : > "$LOG"
echo 'edited' >> "$HOME/.config/hypr/hyprland.lua"
mkdir -p "$HOME/.config/dconf"; echo db > "$HOME/.config/dconf/tinkero"
mkdir -p "$HOME/.local/bin"; printf '#!/bin/bash\nexec mise x claude -- claude "$@"\n' > "$HOME/.local/bin/claude"
# shellcheck disable=SC2016  # the guarded line is written literally, as tinkero-provision writes it
printf 'echo mine\n%s\n' '[[ ${XDG_SESSION_DESKTOP:-} == Hyprland && -r /usr/share/omarchy/default/bash/rc ]] && source /usr/share/omarchy/default/bash/rc  # tinkero-provision' > "$HOME/.bashrc"
out=$("$T" --remove 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 0 "remove: exit 0"
assert_no_path "$HOME/.config/hypr/bindings.lua" "remove: an unchanged seeded file is deleted"
assert_no_path "$HOME/.local/state/omarchy/preinstalls-removed" "remove: the preinstalls marker is deleted"
assert_no_path "$HOME/.XCompose" "remove: the XCompose file is deleted"
assert_file "$HOME/.config/hypr/hyprland.lua" "remove: a changed file is kept"
assert_contains "$out" "kept (you changed it): .config/hypr/hyprland.lua" "remove: and listed"
assert_no_path "$HOME/.claude/skills/omarchy" "remove: skill links are removed"
assert_eq "$(cat "$HOME/.bashrc")" "echo mine" "remove: only the tagged bashrc line goes"
assert_no_path "$HOME/.config/dconf/tinkero" "remove: the session's dconf database is deleted"
assert_file "$HOME/.local/bin/claude" "remove: mise stubs are kept"
assert_contains "$out" "kept (mise stub, remove by hand if unwanted): .local/bin/claude" "remove: and listed"
assert_contains "$(cat "$LOG")" "systemctl --user stop omarchy-keep.service" "remove: the session units are stopped"
assert_no_path "$HOME/.local/state/tinkero" "remove: the state directory is gone"
assert_contains "$out" "sudo dnf remove tinkero" "remove: says what comes next"

# 11b. Robustness (review of plan 2E, Task 4)
# (1) a theme staged headless before a full in-session provision is still applied for real
newhome 16
mkdir -p "$HOME/.local/state/omarchy/current"; echo "Tokyo Night" > "$HOME/.local/state/omarchy/current/theme.name"
FAIL_MISE_WORK=1 "$T" --yes >/dev/null 2>&1 || true
: > "$LOG"; "$T" --session >/dev/null 2>&1 || true
assert_contains "$(cat "$LOG")" "omarchy-theme-set Tokyo Night" "in-session theme: staged headless, applied for real even though the session run was a full provision"
assert_file "$HOME/.local/state/tinkero/done/theme-in-session" "in-session theme: the marker is set"
: > "$LOG"; "$T" --session >/dev/null 2>&1
assert_eq "$(grep -c '^omarchy-theme-set' "$LOG")" 0 "in-session theme: and only once"

# (2) step_skills fails explicitly (errexit does not cross run_step's subshell on its own)
newhome 17
mkdir -p "$HOME/.claude"; : > "$HOME/.claude/skills"
out=$("$T" --yes 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 1 "robustness: a step_skills failure fails the run"
assert_contains "$out" "not complete: skills failed" "robustness: and names it"
assert_no_path "$HOME/.local/state/tinkero/release" "robustness: no release recorded"
: > "$LOG"; "$T" --session >/dev/null 2>&1 && rc=0 || rc=$?
assert_eq "$rc" 1 "robustness: session start still fails when skills keeps failing"
assert_contains "$(cat "$LOG")" "systemctl --user start omarchy-keep.service" "robustness: but the units still start"

# (3) dconf is seeded before the in-session steps run
export HOME=$d/home10   # the no-bus home, provisioned then session-started in block 9
rm -f "$HOME/.local/state/tinkero/done/dconf" "$HOME/.local/state/tinkero/done/hardware"
: > "$LOG"; "$T" --session >/dev/null 2>&1
dconf_line=$(grep -n '^dconf load' "$LOG" | head -n1 | cut -d: -f1)
hw_line=$(grep -n '^leaf hardware' "$LOG" | head -n1 | cut -d: -f1)
if [[ -n $dconf_line && -n $hw_line && $dconf_line -lt $hw_line ]]; then
  ok "robustness: dconf is seeded before the in-session steps run"
else
  not_ok "robustness: dconf is seeded before the in-session steps run" "dconf line=$dconf_line hardware line=$hw_line"
fi

# (4) --remove on a symlinked ~/.bashrc keeps the symlink and the real file's mode
newhome 18
"$T" --yes >/dev/null 2>&1
mkdir -p "$HOME/dots"
# shellcheck disable=SC2016  # the guarded line is written literally, as tinkero-provision writes it
printf 'echo mine\n%s\n' '[[ ${XDG_SESSION_DESKTOP:-} == Hyprland && -r /usr/share/omarchy/default/bash/rc ]] && source /usr/share/omarchy/default/bash/rc  # tinkero-provision' > "$HOME/dots/bashrc"
chmod 600 "$HOME/dots/bashrc"
rm -f "$HOME/.bashrc"; ln -s dots/bashrc "$HOME/.bashrc"
"$T" --remove >/dev/null 2>&1
assert_symlink "$HOME/.bashrc" dots/bashrc "robustness: a symlinked bashrc stays a symlink"
assert_eq "$(cat "$HOME/dots/bashrc")" "echo mine" "robustness: and the guarded line is filtered from the real file"
assert_eq "$(stat -c %a "$HOME/dots/bashrc")" 600 "robustness: the real file's mode is preserved"

# (5) --remove lists and keeps an orphaned row whose target still exists
newhome 19
"$T" --yes >/dev/null 2>&1
rm "$OMARCHY_PATH/applications/foot.desktop"
echo edited >> "$HOME/.local/share/applications/foot.desktop"
"$T" --yes >/dev/null 2>&1
out=$("$T" --remove 2>&1)
assert_contains "$out" "kept (you changed it): .local/share/applications/foot.desktop" "robustness: an orphaned row is listed"
assert_file "$HOME/.local/share/applications/foot.desktop" "robustness: and kept"
"$ROOT/tests/fixtures/make-payload.sh" "$d/payload" >/dev/null

rm -rf "$d"; finish
