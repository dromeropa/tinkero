#!/bin/bash
# make-payload.sh OUTDIR: a stand-in for the installed tinkero payload (usr/share/omarchy,
# usr/share/tinkero, etc/dconf, usr/lib/systemd/user) for the tinkero-provision tests.
# The install/user leaves are one-line scripts that append to $LOG. Prints OUTDIR.
# Re-running over the same OUTDIR restores every fixture file (tests mutate them).
set -euo pipefail
out=$1; o=$out/usr/share/omarchy; t=$out/usr/share/tinkero
mkdir -p "$o"/{config/hypr,config/git,config/chromium/Default,default/hypr/toggles,default/tensaku} \
         "$o"/default/agents/skills/{omarchy,diagnose-crash} "$o"/applications \
         "$o"/install/user/{hardware/asus,first-run} \
         "$t"/{config/hypr,provision,config-notes} "$out/etc/dconf/profile" "$out/usr/lib/systemd/user"
echo 'require("default.hypr.omarchy")' > "$o/config/hypr/hyprland.lua"
echo '-- upstream bindings template' > "$o/config/hypr/bindings.lua"
echo '-- looknfeel v1' > "$o/config/hypr/looknfeel.lua"
printf '[alias]\n\tst = status\n' > "$o/config/git/config"
echo '{"chromium":true}' > "$o/config/chromium/Default/Preferences"
echo '--flag' > "$o/config/chromium-flags.conf"
echo 'ASCII mark' > "$o/icon.txt"
echo 'ASCII logo' > "$o/logo.txt"
echo '-- flags' > "$o/default/hypr/toggles/flags.lua"
echo 'annotation-size-factor = 2.0' > "$o/default/tensaku/state.toml"
echo '# fixture skill' > "$o/default/agents/skills/omarchy/SKILL.md"
echo '# fixture skill' > "$o/default/agents/skills/diagnose-crash/SKILL.md"
printf '[Desktop Entry]\nName=Foot\nExec=foot\n' > "$o/applications/foot.desktop"
printf '[Desktop Entry]\nName=Disk Usage\nExec=xdg-terminal-exec -e dua\n' > "$o/applications/Disk Usage.desktop"
printf '[Desktop Entry]\nName=YouTube\nExec=omarchy-launch-webapp https://youtube.com/\n' > "$o/applications/YouTube.desktop"
printf '[Desktop Entry]\nName=HEY\nExec=omarchy-webapp-handler-hey %%u\n' > "$o/applications/HEY.desktop"
# leaf NAME FILE [EXTRA]: a stand-in for an install/user leaf; it logs its name and the two
# variables the real leaves care about, then runs EXTRA (used to make one leaf fail on demand).
leaf() {
  # shellcheck disable=SC2016  # the leaf expands these variables when it is sourced, not here
  printf 'echo "leaf %s headless=${OMARCHY_THEME_HEADLESS:-} name=${OMARCHY_USER_NAME:-}" >> "$LOG"\n%s\n' "$1" "${3:-}" > "$o/install/user/$2"
}
leaf theme theme.sh
# shellcheck disable=SC2016  # the leaf reads FAIL_MISE_WORK when it is sourced
leaf mise-work mise-work.sh 'if [[ ${FAIL_MISE_WORK:-} == 1 ]]; then exit 1; fi'
leaf mise mise.sh
leaf hardware-asus hardware/asus/fix-mic.sh
leaf hardware-nouveau hardware/fix-nouveau-cursor.sh
leaf audio-tuning first-run/audio-tuning.sh
# upstream's xcompose.sh shape: a heredoc into ~/.XCompose with the user's name from the environment
# shellcheck disable=SC2016
printf 'tee ~/.XCompose >/dev/null <<EOF\ninclude "/usr/share/omarchy/default/xcompose"\n<Multi_key> <space> <n> : "$OMARCHY_USER_NAME"\nEOF\n' > "$o/install/user/xcompose.sh"
echo '-- tinkero bindings: tmux and herdr' > "$t/config/hypr/bindings.lua"
printf 'chromium/\nchromium-flags.conf\n' > "$t/provision/skip.list"
printf '# fixture units\nomarchy-keep.service\nmissing.service\n' > "$t/provision/session-units.list"
printf 'omarchy_tag=v4.0.4\ntinkero_rev=1\n' > "$t/upstream.lock"
echo 'Note for v4.0.4: nothing moved.' > "$t/config-notes/v4.0.4.md"
printf 'user-db:tinkero\nsystem-db:local\n' > "$out/etc/dconf/profile/tinkero"
printf '[Service]\nExecStart=/bin/true\n' > "$out/usr/lib/systemd/user/omarchy-keep.service"
echo "$out"
