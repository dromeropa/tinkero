# tinkero-nerd-fonts.spec: the patched Nerd Fonts the Tinkero shell needs (forked from omedora-nerd-fonts.spec).
#
# Fedora ships plain JetBrains Mono and Cascadia Code, but NOT the Nerd
# Font-patched variants that carry the icon glyphs waybar/terminal/prompt use.
# This packages the upstream patched archives as a normal RPM, so they land in
# the system font dir, fontconfig auto-indexes them, and `dnf remove` cleans
# them up — replacing the per-user source installer.
#
# noarch: fonts are just data files, identical on every CPU architecture.

Name:           tinkero-nerd-fonts
Version:        3.4.0
Release:        1%{?dist}
Summary:        CascadiaCode + JetBrainsMono Nerd Fonts for Tinkero

License:        MIT and OFL-1.1
URL:            https://github.com/ryanoasis/nerd-fonts

# Two upstream archives — one per font family. spectool -g downloads both.
Source0:        %{url}/releases/download/v%{version}/CascadiaCode.tar.xz
Source1:        %{url}/releases/download/v%{version}/JetBrainsMono.tar.xz

BuildArch:      noarch

# fontconfig owns the font cache + provides the file trigger that reindexes
# /usr/share/fonts when our files land.
Requires:       fontconfig

%description
The Nerd Font-patched CascadiaCode (CaskaydiaMono/Cove) and JetBrainsMono
families, providing the icon glyphs Tinkero's shell and terminal
prompt render. Bundles ryanoasis/nerd-fonts release archives.

%prep
# -c -T makes an empty build dir; we unpack the two .tar.xz archives by hand
# (they have no common top-level directory).
%setup -q -c -T
mkdir -p cascadia jetbrains
tar -xJf %{SOURCE0} -C cascadia
tar -xJf %{SOURCE1} -C jetbrains

%build
# Nothing to compile.

%install
fontdir=%{buildroot}%{_datadir}/fonts/tinkero-nerd-fonts
install -d "$fontdir"
# Ship the actual font files only (skip the archives' READMEs/licenses here;
# the license text is covered by the License: field).
find cascadia jetbrains \( -name '*.ttf' -o -name '*.otf' \) \
    -exec install -m 0644 -t "$fontdir" {} +

%files
%dir %{_datadir}/fonts/tinkero-nerd-fonts
%{_datadir}/fonts/tinkero-nerd-fonts/*

%changelog
* Fri May 29 2026 Tinkero <noreply@tinkero.invalid> - 3.4.0-1
- Package CascadiaCode + JetBrainsMono Nerd Fonts (ryanoasis v3.4.0).
