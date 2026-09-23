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

# Task 4 appends its cases here.
rm -rf "$d"; finish
