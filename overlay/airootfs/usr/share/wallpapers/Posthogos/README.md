# Wallpaper package: Posthogos

A KPackage-style wallpaper bundle. Plasma reads `metadata.desktop` to know
the wallpaper's name and authorship, and pulls the actual image from
`contents/images/`.

## Required files

```
overlay/airootfs/usr/share/wallpapers/Posthogos/
├── metadata.desktop
└── contents/
    └── images/
        ├── 1920x1080.png       # one image per common aspect
        ├── 2560x1440.png       # Plasma picks the closest match
        └── 3840x2160.png
```

`metadata.desktop`:

```ini
[Desktop Entry]
Name=PosthogOS
X-KDE-PluginInfo-Name=Posthogos
X-KDE-PluginInfo-Author=PosthogOS
X-KDE-PluginInfo-Email=
X-KDE-PluginInfo-License=CC-BY-SA-4.0
```

## Source artwork

Editable masters live in `branding/posthogos/` at the repo root. Export
sized PNGs from there and drop them in `contents/images/`. Don't commit
giant PSDs in `overlay/` — that's `branding/posthogos/`'s job.
