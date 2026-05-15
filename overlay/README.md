# overlay/

Files here are rsync'd onto `upstream/archiso/` at build time. The directory
structure mirrors `archiso/` exactly. A file at
`overlay/airootfs/usr/share/wallpapers/posthogos/foo.png` lands at
`/usr/share/wallpapers/posthogos/foo.png` inside the live system, and a file
at `overlay/grub/grub.cfg` overrides `archiso/grub/grub.cfg` for the build.

Overlay wins: if a file exists in both `upstream/archiso/` and `overlay/`,
the overlay copy is what ends up in the build.

**Important: don't put files in `overlay/airootfs/` that are owned by
packages installed during pacstrap** (e.g. `/etc/os-release` → `filesystem`,
`/etc/lsb-release` → `lsb-release`, `/etc/sudoers` → `sudo`). pacstrap
refuses to overwrite pre-staged files and the build dies with
`error: failed to commit transaction (conflicting files)`. Write those
in `scripts/posthogos-customize.sh` instead, which runs in the chroot
after pacstrap completes.

## Layout

```
overlay/
├── airootfs/             # → archiso/airootfs/ (live system file overlay)
│   └── etc/
│       ├── os-release
│       └── lsb-release
├── grub/                 # → archiso/grub/   (UEFI GRUB boot menu, not yet)
├── syslinux/             # → archiso/syslinux/ (BIOS boot menu,    not yet)
└── efiboot/              # → archiso/efiboot/ (systemd-boot,       not yet)
```

## Three layers, three purposes

| Layer                            | When           | What for                                         |
|----------------------------------|----------------|--------------------------------------------------|
| `overlay/`                       | pre-build      | net-new files + full-shadow files we own         |
| `scripts/pre-build.sh`           | pre-build      | narrow sed-patches against upstream-owned files  |
| `scripts/posthogos-customize.sh` | inside chroot  | runtime setup (mkinitcpio, caches, sed-patches)  |

Why three: full-shadowing every upstream-owned file via overlay risks losing
new entries when upstream evolves. For things like `profiledef.sh` (where we
only care about a few identity fields) and `/etc/calamares/settings.conf`
(owned by `cachyos-calamares-next`), narrow sed-patches keep us rebase-safe.

## What lives where

| File                                                | Where                  |
|-----------------------------------------------------|------------------------|
| `etc/os-release`, `etc/lsb-release`                 | `posthogos-customize`  |
| Plymouth/SDDM/Plasma/Calamares theme dirs           | `overlay/airootfs/`    |
| `etc/skel/.config/` defaults                        | `overlay/airootfs/`    |
| ISO name/label/publisher                            | `scripts/pre-build.sh` |
| `/etc/calamares/settings.conf` branding key         | `posthogos-customize`  |
| `/etc/plymouth/plymouthd.conf` + `mkinitcpio -P`    | `posthogos-customize`  |
| SDDM `Current=posthogos` config                     | `posthogos-customize`  |
| Boot menu titles (grub.cfg, syslinux.cfg, loader)   | `overlay/` (TBD)       |
