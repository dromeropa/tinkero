# shellcheck shell=bash
# Sourced by the omarchy-pkg-* replacements (installed at /usr/share/tinkero/pkg.sh).
# The name map, /usr/share/tinkero/pkgmap.tsv, has one row per Arch package name
# that anything in the payload passes to a package wrapper:
#   arch-name <TAB> kind <TAB> target      kind is dnf, flatpak or none
TINKERO_PKGMAP=${TINKERO_PKGMAP:-/usr/share/tinkero/pkgmap.tsv}

# pkg_map ARCH-NAME: print "kind<TAB>target"; return 1 when the name has no row.
pkg_map() {
  local line
  line=$(awk -F'\t' -v n="$1" '$1 == n { print $2 "\t" $3; exit }' "$TINKERO_PKGMAP")
  [[ -n $line ]] || return 1
  printf '%s\n' "$line"
}

# pkg_installed ARCH-NAME: 0 when the mapped package is installed.
pkg_installed() {
  local kind target
  IFS=$'\t' read -r kind target < <(pkg_map "$1") || return 1
  case $kind in
    dnf)     rpm -q "$target" &>/dev/null ;;
    flatpak) flatpak info "$target" &>/dev/null ;;
    *)       return 1 ;;
  esac
}

# pkg_unmapped_notice ARCH-NAME: explain what to do by hand.
pkg_unmapped_notice() {
  cat >&2 <<EOF
Tinkero: no Fedora package is mapped for '$1'.
Install it by hand ('dnf search $1' or 'flatpak search $1'), and if that works,
add a row for it to $TINKERO_PKGMAP so the menu and the agent know about it.
EOF
}

# elevate CMD...: run as root. pkexec inside a graphical session (the shell's polkit
# dialog answers it, which an agent's terminal cannot); sudo over SSH or on a console.
elevate() {
  # TINKERO_EUID is a test seam (the suite runs as root in CI). A string comparison, not
  # arithmetic, so an odd value in the environment cannot be evaluated as an expression.
  # pkexec runs the command in / with a scrubbed environment: pass everything as arguments.
  if [[ ${TINKERO_EUID:-$EUID} == 0 ]]; then "$@"
  elif [[ -n ${WAYLAND_DISPLAY:-} || -n ${DISPLAY:-} ]]; then pkexec "$@"
  else sudo "$@"
  fi
}
