#!/bin/bash
# patches/0014-fastfetch-config-name-fedora.patch (issue #50): the About screen's OS line
# carried only the Tinkero/Omarchy attribution and never named the host distro, because the
# branding substitution (branding/strings.tsv) rewrites that row's text instead of adding to
# it. The patch adds fastfetch's own "os" module (reads /etc/os-release, needs no
# Tinkero-specific text) next to the rewritten row. Applies the real patch and the real
# strings.tsv row to a realistic stand-in of the upstream file and asserts the rendered
# config names both.
source "$(dirname "$0")/lib.sh"
d=$(mktmp); tree=$d/tree; mkdir -p "$tree/etc/fastfetch"

cat > "$tree/etc/fastfetch/config.jsonc" <<'S'
    {
      "type": "command",
      "key": " OS",
      "keyColor": "blue",
      "text": "version=$(omarchy-version) && echo \"Omarchy $version\""
    },
    {
      "type": "command",
      "key": "│ ├󰘬",
      "keyColor": "blue",
      "text": "omarchy-version-branch"
    },
S

( cd "$tree" && git apply -p1 "$ROOT/patches/0014-fastfetch-config-name-fedora.patch" ) ||
  { echo "patch 0014-fastfetch-config-name-fedora.patch did not apply" >&2; exit 2; }
assert_contains "$(cat "$tree/etc/fastfetch/config.jsonc")" '"type": "os"' \
  "patch adds fastfetch's own os module"

row=$(grep '^etc/fastfetch/config.jsonc' "$ROOT/branding/strings.tsv")
tsv=$d/strings.tsv
printf '# test\n%s\n' "$row" > "$tsv"
out=$(python3 "$ROOT/branding/apply-strings" "$tree" "$tsv" 2>&1) || { echo "$out" >&2; exit 2; }

rendered=$(cat "$tree/etc/fastfetch/config.jsonc")
# shellcheck disable=SC2016  # the $version below is the rendered file's literal text, not this shell's
assert_contains "$rendered" 'echo \"Tinkero $version, built on Omarchy\"' \
  "rendered config keeps the Tinkero attribution"
assert_contains "$rendered" '"type": "os"' \
  "rendered config still has the Fedora-naming os module alongside it"

rm -rf "$d"; finish
