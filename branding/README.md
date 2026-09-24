# Branding inputs

Everything a user sees that used to say or show Omarchy is generated at build time from
this directory (design spec 4.13; plan 2D, `docs/superpowers/plans/2026-09-23-phase-2d-branding.md`).
Identifiers (`omarchy-*` commands, paths, plugin ids, the font family name) keep upstream's names.

| File | Used for | Constraints |
|---|---|---|
| `mark.svg` | the glyph at `U+E900` of the icon font (the bar's menu button, the "Packages" row), `icon.png` | one SVG with a `viewBox`; `<path>` and the basic shapes (`rect`, `circle`, `ellipse`, `polygon`, `line`); no `transform` attributes (flatten them first); `fill="currentColor"`; monochrome, the shell colours it |
| `wordmark.svg` | the flat wallpaper of every theme that ships one (rendered in the theme's accent on its background), `logo.svg` | same rules; `currentColor` is replaced by the accent before rendering |
| `icon.txt` | the About screen's logo (seeded to `~/.config/omarchy/branding/about.txt`) | at most 54 columns by 26 rows |
| `logo.txt` | the screensaver and the floating-terminal presentation screens | at most 26 rows; width is free |
| `strings.tsv` | exact upstream strings replaced during the build: `file`, `upstream`, `replacement`, `count`, tab-separated, file relative to the upstream tree | the build fails unless every row matches its count |
| `images.tsv` | every wallpaper in the upstream tree with a person's verdict: `keep`, `regenerate` (a flat wordmark, rendered anew), `delete`, or `review` (not looked at yet; the build refuses it) | regenerate the rows with `branding/inventory-images`, look at the images with `branding/contact-sheet` |

The tools (`rebuild-font`, `apply-strings`, `rewrite-manifests`, `render-wallpapers`) are run by
`build/assemble` step 3d and never carry a name, a string or a verdict of their own.

## The artwork is a placeholder

`mark.svg` is a block "T" and `wordmark.svg` is "TINKERO" in block letters; the two text files
are the same shapes in block characters. To replace them with the real mark:

1. Drop in `mark.svg` and `wordmark.svg` (constraints above).
2. Regenerate the text renderings with upstream's own tool from an assembled payload
   (`./dev payload`; needs ImageMagick):

   ```bash
   PATH=$PWD/.cache/payload/usr/bin:$PATH omarchy-transcode-ascii branding/mark.svg branding/icon.txt --width 54 --height 26 --mode block
   PATH=$PWD/.cache/payload/usr/bin:$PATH omarchy-transcode-ascii branding/wordmark.svg branding/logo.txt --width 82 --height 10 --mode block
   ```

3. `./dev gates`: the font, the wallpapers, `icon.png` and `logo.svg` are rendered from the
   SVGs at build time. Nothing else changes.

## Reviewing wallpapers after a bump

```bash
./dev payload
mkdir -p .cache/tree && tar -xzf .cache/omarchy-*.tar.gz -C .cache/tree --strip-components=1
branding/inventory-images .cache/tree branding/images.tsv     # new or changed images become "review"
branding/contact-sheet .cache/tree .cache/wallpapers.png       # look at them
```

Then edit the `review` rows: `keep` for an image with nothing branded, `regenerate` for a flat
wordmark on a plain background (the name must contain `omarchy`; the theme's `colors.toml`
supplies the colours), `delete` for anything else that shows upstream's marks.
