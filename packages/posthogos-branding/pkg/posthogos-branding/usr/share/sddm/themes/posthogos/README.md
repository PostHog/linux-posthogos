# SDDM theme: posthogos

Activated by [scripts/posthogos-customize.sh](../../../../../../../scripts/posthogos-customize.sh)
once `Main.qml` + `metadata.desktop` exist here. Until then the hook leaves
the CachyOS default in place.

## Required files

| File              | Format       | Notes                                                       |
|-------------------|--------------|-------------------------------------------------------------|
| `Main.qml`        | QML          | Greeter UI. Username/password input + login button minimum. |
| `metadata.desktop`| desktop file | Theme metadata (name, description, author).                 |
| `theme.conf`      | INI          | Theme configuration (colors, background image path).        |
| `background.jpg`  | JPG/PNG      | Login screen background.                                    |
| `logo.png`        | PNG          | Branded logo above the input fields.                        |

## Reference themes to fork

- `sddm-sugar-candy-git` (AUR): most popular community theme, clean QML
- `sddm-theme-where-is-my-sddm-theme-git`: minimal, easy to restyle
- The default `breeze` theme at `/usr/share/sddm/themes/breeze/`

## Minimal `metadata.desktop`

```ini
[SddmGreeterTheme]
Name=PosthogOS
Description=PosthogOS login theme
Author=PosthogOS
Copyright=© PosthogOS
License=MIT
Type=sddm-theme
Version=0.1
Website=
Screenshot=preview.png
MainScript=Main.qml
ConfigFile=theme.conf
TranslationsDirectory=translations
Theme-Id=posthogos
Theme-API=2.0
```
