# shellcheck shell=bash
# Shared staging logic for the .deb and .rpm builders.
#
# Both formats are produced by repackaging the already-built portable pacman
# packages (`posthogos-*.pkg.tar.zst`) — a pacman package is just a tar of the
# staged file tree plus a few dotfile metadata members. Reusing it keeps the
# downstream packages byte-for-byte identical to what Arch ships and means the
# file layout has exactly one source of truth (each PKGBUILD's package()).
#
# Source this file; it defines two functions and no side effects.

# posthogos_upstream_version <raw_pkgver> -> echoes a deb/rpm upstream version.
#
# Maps both pre-release separators to '~', which sorts BELOW the empty string
# in Debian *and* rpm version ordering (unlike '-'/'_', which sort above). So
# 0.3.0~beta.1 < 0.3.0 in both ecosystems, and an apt/dnf user on a beta will
# upgrade to the final release. Strips a leading 'v'.
#   - '_'       : the pacman pkgver normalization (0.0.1_alpha.1)
#   - first '-' : the semver pre-release separator from a release tag
#                 (0.3.0-beta.1). Only the first; callers append their own
#                 revision (deb '-1' / rpm release) separately.
posthogos_upstream_version() {
    local v="${1#v}"
    v="${v//_/\~}"
    v="${v/-/\~}"
    printf '%s' "$v"
}

# _posthogos_sed_inplace <file> <sed-args...> — portable in-place sed (works
# under both GNU and BSD sed; avoids the -i suffix incompatibility).
_posthogos_sed_inplace() {
    local f="$1"; shift
    local tmp="${f}.posthogos.tmp"
    sed "$@" "$f" > "$tmp" && mv "$tmp" "$f"
}

# _posthogos_relocate_usr_local_bin <root> — Debian/Fedora both reserve
# /usr/local for the local admin, so packaged executables must live in
# /usr/bin. posthogos-scripts ships them under /usr/local/bin on Arch; move
# the tree and rewrite the absolute paths that reference OUR binaries
# (posthogos-*, neohog, papirus-folders). Third-party tools that
# posthogos-toolkit-install drops into /usr/local/bin at runtime (op, asdf)
# legitimately belong there and are left untouched by the targeted patterns.
_posthogos_relocate_usr_local_bin() {
    local root="$1"
    [ -d "$root/usr/local/bin" ] || return 0
    echo "  relocating /usr/local/bin -> /usr/bin" >&2
    install -d "$root/usr/bin"
    cp -a "$root/usr/local/bin/." "$root/usr/bin/"
    rm -rf "$root/usr/local"

    local f
    while IFS= read -r -d '' f; do
        _posthogos_sed_inplace "$f" \
            -e 's#/usr/local/bin/posthogos-#/usr/bin/posthogos-#g' \
            -e 's#/usr/local/bin/neohog#/usr/bin/neohog#g' \
            -e 's#/usr/local/bin/papirus-folders#/usr/bin/papirus-folders#g'
    done < <(find "$root/usr/bin" "$root/etc" "$root/usr/lib/systemd" -type f -print0 2>/dev/null)
}

# stage_posthogos_pkg <pkgname> <src_dir> <dest_root>
# Extract the newest matching pacman package into dest_root, drop pacman
# metadata, and relocate /usr/local/bin. Leaves the license where pacman put
# it (/usr/share/licenses/<pkg>/) — the rpm convention; the deb builder moves
# it to /usr/share/doc afterwards. Returns non-zero if no package is found.
stage_posthogos_pkg() {
    local pkg="$1" src_dir="$2" root="$3"
    local src
    src=$(ls -1t "$src_dir/$pkg"-*.pkg.tar.zst 2>/dev/null | head -n1 || true)
    [ -n "$src" ] || { echo "ERROR: no $pkg-*.pkg.tar.zst found in $src_dir (run bin/build first)" >&2; return 1; }
    echo "  $pkg <- $(basename "$src")" >&2

    mkdir -p "$root"
    chmod 755 "$root"   # mktemp -d is 0700; package root maps to / perms
    tar --zstd -xf "$src" -C "$root"
    rm -f "$root"/.PKGINFO "$root"/.BUILDINFO "$root"/.MTREE "$root"/.INSTALL "$root"/.CHANGELOG

    _posthogos_relocate_usr_local_bin "$root"
}
