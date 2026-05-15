# branding/posthogos/

Source artwork for the PosthogOS brand. Keep editable masters here (SVG, full-
res PNG sources, Figma exports). The build does not consume these directly;
processed outputs (correctly-sized PNGs, theme files) belong in `overlay/`.

## Expected files

| File                  | Used in                                                |
|-----------------------|--------------------------------------------------------|
| `logo.svg`            | Plymouth splash, SDDM theme, Calamares welcome screen  |
| `wallpaper-4k.png`    | Source for `overlay/usr/share/wallpapers/Posthogos/`   |
| `slideshow/*.png`     | Calamares installer slideshow                          |
| `colors.txt`          | Hex values for color scheme + GTK theme                |

When you add a new asset here, also wire it into `overlay/` so the build picks
it up. Nothing under `branding/` ends up in the ISO automatically.
