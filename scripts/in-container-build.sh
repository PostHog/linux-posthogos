#!/usr/bin/env bash
# Runs inside the posthogos-builder container (or natively on Arch).
# Assembles a writable build tree from upstream/ + overlay/, then invokes
# buildiso.sh to produce the ISO.
#
# Expected env:
#   KEEP_BUILD=true|false   (default false) — keep build/ work tree after build

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

echo "==> Applying overlay/ → archiso/airootfs/"
if [ -d overlay ] && [ -n "$(ls -A overlay 2>/dev/null)" ]; then
    rsync -a --info=stats1 overlay/ "$build_dir/archiso/airootfs/"
else
    echo "    (overlay/ is empty — nothing to merge)"
fi

echo "==> Installing chroot hook"
mkdir -p "$build_dir/archiso/airootfs/root"
install -m 0755 scripts/posthogos-customize.sh \
    "$build_dir/archiso/airootfs/root/posthogos-customize.sh"

# Hook the customize script into the build via a systemd oneshot, or by
# patching util-iso.sh. For now: drop a shell-profile snippet that runs at
# the end of pacstrap. mkarchiso runs scripts under airootfs/root/ via
# customize_airootfs.sh by convention if present at that path.
cp scripts/posthogos-customize.sh "$build_dir/archiso/airootfs/root/customize_airootfs.sh"
chmod +x "$build_dir/archiso/airootfs/root/customize_airootfs.sh"

echo "==> Running upstream buildiso.sh"
cd "$build_dir"
buildiso_args=(-p desktop -v)
[ "${KEEP_BUILD:-false}" = "true" ] || buildiso_args+=(-w)

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
