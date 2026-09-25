#!/bin/bash
# make-tree.sh OUTDIR: build a tiny stand-in for the upstream tree and tar it
# the way GitHub does (one top-level directory). Prints the tarball path.
set -euo pipefail
out=$1; top=$out/omarchy-fixture
mkdir -p "$top"/{bin,shell/plugins/menu,migrations,etc/fastfetch,etc/mise/conf.d,etc/sudoers.d} \
         "$top"/default/{pacman,uwsm/env.d,systemd/user,fonts/omarchy,fontconfig/conf.avail,omarchy,agents/skills/omarchy} \
         "$top"/applications/icons
mk() { printf '#!/bin/bash\n%s\n' "$2" > "$top/bin/$1"; chmod 755 "$top/bin/$1"; }
mk omarchy-keep-me      'echo kept'
mk omarchy-version      'pacman -Q omarchy'
mk omarchy-update       'sudo pacman -Syu'
mk omarchy-snapshot     'snapper create'
mk omarchy-plymouth-set 'plymouth-set-default-theme'
mk omarchy-calls-dropped 'omarchy-snapshot create'
echo 4.0.0.alpha > "$top/version"
echo 'MIT' > "$top/LICENSE"
echo '[options]' > "$top/default/pacman/pacman.conf"
echo 'export OMARCHY_PATH=/usr/share/omarchy' > "$top/default/uwsm/env.d/10-omarchy"
printf '[Unit]\nDescription=Keep me\n\n[Install]\nWantedBy=graphical-session.target\n\n[Service]\nExecStart=/usr/bin/omarchy-keep-me\n' > "$top/default/systemd/user/omarchy-keep.service"
printf '[Service]\nExecStart=/usr/bin/omarchy-migrate-notify\n\n[Install]\nWantedBy=graphical-session.target\n' > "$top/default/systemd/user/omarchy-migrate-notify.service"
printf '[Unit]\nDescription=No install section\n\n[Service]\nExecStart=/usr/bin/true\n' > "$top/default/systemd/user/omarchy-no-install.service"
echo font > "$top/default/fonts/omarchy/omarchy.ttf"
echo '<fontconfig/>' > "$top/default/fontconfig/conf.avail/50-omarchy.conf"
echo '# fixture skill' > "$top/default/agents/skills/omarchy/SKILL.md"
echo 'png' > "$top/applications/icons/Disk Usage.png"
echo 'png' > "$top/applications/icons/imv.png"
cat > "$top/default/omarchy/omarchy-menu.jsonc" <<'J'
{
  // fixture menu
  "learn": {"icon":"","label":"Learn"},
  "learn.arch": {"icon":"","label":"Arch","action":"omarchy-launch-webapp 'https://wiki.archlinux.org/'"},
  "update": {"icon":"","label":"Update"},
  "update.snap": {"icon":"","label":"Snapshot","action":"omarchy-snapshot create"},
}
J
echo '{"text":"Omarchy"}' > "$top/etc/fastfetch/config.jsonc"
echo '[tool_alias]' > "$top/etc/mise/conf.d/omarchy.toml"
echo '%wheel ALL=(root) NOPASSWD: ALL' > "$top/etc/sudoers.d/omarchy-dns"
echo 'migration' > "$top/migrations/1.sh"
tar -C "$out" -czf "$out/fixture.tar.gz" omarchy-fixture
echo "$out/fixture.tar.gz"
