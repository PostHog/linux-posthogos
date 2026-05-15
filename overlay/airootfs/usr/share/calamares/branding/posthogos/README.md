# Calamares branding: posthogos

Activated by [scripts/posthogos-customize.sh](../../../../../../../scripts/posthogos-customize.sh)
once `branding.desc` exists here. The hook sed-patches
`/etc/calamares/settings.conf` to flip `branding: cachyos` → `branding: posthogos`.

Until `branding.desc` exists, the hook leaves the upstream CachyOS branding
selected (so the installer still works).

## Required files

| File              | Format       | Notes                                              |
|-------------------|--------------|----------------------------------------------------|
| `branding.desc`   | YAML         | Strings, image paths, color palette, slideshow ref |
| `show.qml`        | QML          | Installer slideshow                                |
| `logo.png`        | PNG          | Top-left logo                                      |
| `welcome.png`     | PNG          | Welcome screen image                               |
| `slideshow/*.png` | PNGs         | Slideshow frames                                   |

## Reference branding to copy

`/usr/share/calamares/branding/cachyos/` on a CachyOS live image (ships with
`cachyos-calamares-next`). Copy the dir, swap PNGs, edit the strings.

## Critical strings in `branding.desc`

```yaml
componentName: posthogos
welcomeStyleCalamares: true
welcomeExpandingLogo: true
strings:
    productName:         PosthogOS
    shortProductName:    PosthogOS
    version:             rolling
    shortVersion:        rolling
    versionedName:       PosthogOS rolling
    shortVersionedName:  PosthogOS rolling
    bootloaderEntryName: PosthogOS
    productUrl:          https://github.com/posthog/linux-posthogos
    supportUrl:          https://github.com/posthog/linux-posthogos/issues
    knownIssuesUrl:      https://github.com/posthog/linux-posthogos/issues
images:
    productLogo:         logo.png
    productIcon:         logo.png
    productWelcome:      welcome.png
slideshow:               show.qml
```
