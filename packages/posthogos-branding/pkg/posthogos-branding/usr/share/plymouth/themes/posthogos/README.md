# Plymouth theme: posthogos

Activated by [scripts/posthogos-customize.sh](../../../../../../../scripts/posthogos-customize.sh)
once `posthogos.plymouth` exists here. Until then the hook leaves the
CachyOS default in place.

## Required files

| File              | Format                            | Notes                                                |
|-------------------|-----------------------------------|------------------------------------------------------|
| `posthogos.plymouth` | INI                            | Theme descriptor. See `/usr/share/plymouth/themes/*/example.plymouth` on any system with plymouth installed. |
| `posthogos.script`   | Plymouth scripting language    | Renders the splash. Easiest start: copy `details.script` from the plymouth pkg and add logo image. |
| `logo.png`           | PNG, 256×256 or larger, transparent BG | Source: `branding/posthogos/logo.svg` exported at the right size. |
| `background.png`     | optional                       | Full-screen background if not pure black.            |

## Minimal descriptor template (`posthogos.plymouth`)

```ini
[Plymouth Theme]
Name=PosthogOS
Description=PosthogOS boot splash
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/posthogos
ScriptFile=/usr/share/plymouth/themes/posthogos/posthogos.script
```

## Reference theme to copy

CachyOS ships a Plymouth theme in `/usr/share/plymouth/themes/cachyos/`
on any live image. Fork it as a starting point: rename files, swap PNGs,
edit the .script to reference `posthogos` instead of `cachyos`.
