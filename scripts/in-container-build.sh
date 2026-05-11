#!/usr/bin/env bash
# Runs inside the posthogos-builder container (or natively on Arch).
# Assembles a writable build tree from upstream/ + overlay/, then invokes
# buildiso.sh to produce the ISO.
#
# Expected env:
#   KEEP_BUILD=1   (default 0) — keep build/ work tree after build
#   FAST_BUILD=1   (default 0) — use zstd not xz for squashfs (see pre-build.sh)

set -euo pipefail

cd "$(dirname "$0")/.."
repo_root="$PWD"

if [ ! -d upstream/archiso ]; then
    echo "Missing upstream/archiso. Run: git submodule update --init upstream" >&2
    exit 1
fi

build_dir="$repo_root/build"
out_dir="$repo_root/out"
mkdir -p "$out_dir"

echo "==> Resetting build tree at $build_dir"
rm -rf "$build_dir"
mkdir -p "$build_dir"
# git archive gives the checked-in tree without the submodule .git pointer.
git -C upstream archive --format=tar HEAD | tar -x -C "$build_dir"

echo "==> Applying overlay/ → archiso/"
if [ -d overlay ] && find overlay -mindepth 1 -not -name '.gitkeep' -not -name 'README.md' \
        | grep -q .; then
    rsync -a --info=stats1 \
        --exclude='.gitkeep' --exclude='README.md' \
        overlay/ "$build_dir/archiso/"
else
    echo "    (overlay/ has no payload files — skipping)"
fi

echo "==> Running pre-build patches"
"$repo_root/scripts/pre-build.sh" "$build_dir"

echo "==> Installing chroot hook"
# mkarchiso runs airootfs/root/customize_airootfs.sh inside the chroot at
# squashfs assembly time if present at that exact path.
install -D -m 0755 scripts/posthogos-customize.sh \
    "$build_dir/archiso/airootfs/root/customize_airootfs.sh"

echo "==> Running upstream buildiso.sh"
cd "$build_dir"
buildiso_args=(-p desktop -v)
[ "${KEEP_BUILD:-0}" = "1" ] || buildiso_args+=(-w)

# buildiso.sh requires root for bind mounts. sudo -E preserves env when not
# already root (native path); inside container we run as root already.
if [ "$(id -u)" -eq 0 ]; then
    ./buildiso.sh "${buildiso_args[@]}"
else
    sudo -E ./buildiso.sh "${buildiso_args[@]}"
fi

echo "==> Copying ISO to out/"
shopt -s nullglob
iso_files=("$build_dir"/out/*.iso)
if [ ${#iso_files[@]} -eq 0 ]; then
    echo "ERROR: no ISO produced under $build_dir/out/" >&2
    exit 1
fi
for f in "${iso_files[@]}"; do
    cp -v "$f" "$out_dir/"
done

echo "==> Done. ISO(s) at:"
ls -lh "$out_dir"/*.iso
