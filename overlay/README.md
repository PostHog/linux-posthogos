# overlay/

Files here are rsync'd onto `upstream/archiso/airootfs/` at build time. The
directory structure mirrors `airootfs/` exactly — i.e. a file at
`overlay/usr/share/wallpapers/posthogos/foo.png` lands at
`/usr/share/wallpapers/posthogos/foo.png` in the live system.

Overlay wins: if a file exists in both `upstream/` and `overlay/`, the overlay
copy is what ends up in the squashfs.

## What lives here

| Path                                                    | Purpose                                |
|---------------------------------------------------------|----------------------------------------|
| `etc/os-release`                                        | Override CachyOS identity              |
| `etc/lsb-release`                                       | Same                                   |
| `etc/skel/.config/kdeglobals`                           | Default Plasma color scheme + L&F      |
| `etc/skel/.config/gtk-3.0/settings.ini`                 | Default GTK theme                      |
| `etc/skel/.config/gtk-4.0/settings.ini`                 | Same                                   |
| `usr/share/plymouth/themes/posthogos/`                  | Boot splash                            |
| `usr/share/sddm/themes/posthogos/`                      | Login screen                           |
| `usr/share/plasma/look-and-feel/com.posthog.posthogos/` | Plasma global theme                    |
| `usr/share/color-schemes/Posthogos.colors`              | Plasma color scheme                    |
| `usr/share/themes/Posthogos-gtk/`                       | GTK theme                              |
| `usr/share/wallpapers/Posthogos/`                       | Default wallpaper package              |
| `usr/share/calamares/branding/posthogos/`               | Installer branding                     |

## What does NOT live here

- `etc/calamares/settings.conf` — that file is owned by `cachyos-calamares-next`
  and gets sed-patched at chroot time. See `scripts/posthogos-customize.sh`.
- `etc/plymouth/plymouthd.conf` — written by the chroot hook for the same reason.

## Boot menu titles

`overlay/` does NOT cover the bootloader configs under `upstream/archiso/grub/`,
`upstream/archiso/syslinux/`, `upstream/archiso/efiboot/`. Those are outside
`airootfs/` so the rsync doesn't reach them. Either:
- (current) edit `upstream/` in place and accept that rebases will conflict, or
- (future) extend `scripts/in-container-build.sh` to apply a second overlay for
  the non-airootfs paths.
