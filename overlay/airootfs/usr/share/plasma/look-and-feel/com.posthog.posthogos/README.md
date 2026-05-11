# Plasma global theme (look-and-feel): com.posthog.posthogos

A Plasma "Global Theme" bundle. It's the top-level package that ties
together a color scheme, icon theme, GTK theme, Plasma style, cursor theme,
and wallpaper — so setting it once configures everything below.

Activated by `overlay/airootfs/etc/skel/.config/kdeglobals` pointing
`LookAndFeelPackage=com.posthog.posthogos` (not yet written).

## Required files

| File                   | Format       | Notes                                       |
|------------------------|--------------|---------------------------------------------|
| `metadata.json`        | JSON         | Package ID, name, version                   |
| `contents/defaults`    | INI          | Default for each Plasma component           |
| `contents/previews/*`  | PNG          | Optional preview images for the system settings UI |

## Reference theme to copy

`/usr/share/plasma/look-and-feel/org.kde.breeze.desktop/` on any KDE system.
CachyOS ships its own (`org.cachyos.desktop`) — easier base since it already
has CachyOS defaults wired up.

## Minimal `metadata.json`

```json
{
    "KPlugin": {
        "Id": "com.posthog.posthogos",
        "Name": "PosthogOS",
        "Description": "PosthogOS Plasma global theme",
        "Version": "0.1",
        "Authors": [{ "Name": "PosthogOS" }],
        "License": "MIT"
    },
    "X-Plasma-APIVersion": 7,
    "X-Plasma-ServiceTypes": ["Plasma/LookAndFeel"]
}
```

## Minimal `contents/defaults`

```ini
[kdeglobals][General]
ColorScheme=Posthogos

[kdeglobals][KDE]
LookAndFeelPackage=com.posthog.posthogos
widgetStyle=Breeze

[kdeglobals][Icons]
Theme=breeze

[Wallpaper]
Image=/usr/share/wallpapers/Posthogos/
```
