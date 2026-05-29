#!/usr/bin/env python3
"""Prune superseded packages from a pacman repo directory.

Keeps the N newest versions of each (pkgname, arch) and deletes older
package files plus their detached .sig signatures. Database files
(*.db, *.files and their .tar.* / .sig variants) and anything that
isn't a *.pkg.tar.* are left untouched.

Why this exists: the gh-pages deploy uses `keep_files: true` (load-bearing
for multi-arch + .nojekyll), so every release's packages accumulate
forever even though the published posthogos.db only ever references the
latest build. Those orphans are never fetched by `pacman -Syu`; they just
consume the Pages quota. This prunes them while retaining a small
downgrade window.

No external dependencies (no paccache / zstd / pyalpm): version ordering
is a faithful port of pacman's rpmvercmp (lib/libalpm/version.c).
"""

import argparse
import functools
import os
import sys
from collections import defaultdict

PKG_SUFFIXES = (".pkg.tar.zst", ".pkg.tar.xz", ".pkg.tar.gz", ".pkg.tar")


def _vercmp_segment(a, b):
    """Faithful port of pacman's rpmvercmp() for a single version string."""
    if a == b:
        return 0
    i = j = 0
    pi = pj = 0
    la, lb = len(a), len(b)
    while i < la and j < lb:
        while i < la and not a[i].isalnum():
            i += 1
        while j < lb and not b[j].isalnum():
            j += 1
        if not (i < la and j < lb):
            break
        # Different separator lengths => the shorter-separator side is older.
        if (i - pi) != (j - pj):
            return -1 if (i - pi) < (j - pj) else 1
        pi, pj = i, j
        if a[pi].isdigit():
            while pi < la and a[pi].isdigit():
                pi += 1
            while pj < lb and b[pj].isdigit():
                pj += 1
            isnum = True
        else:
            while pi < la and a[pi].isalpha():
                pi += 1
            while pj < lb and b[pj].isalpha():
                pj += 1
            isnum = False
        seg_a, seg_b = a[i:pi], b[j:pj]
        # seg_a is guaranteed non-empty; empty seg_b means the segment types
        # differ (one numeric, one alpha). Numeric always wins.
        if seg_b == "":
            return 1 if isnum else -1
        if isnum:
            sa, sb = seg_a.lstrip("0"), seg_b.lstrip("0")
            if len(sa) != len(sb):
                return 1 if len(sa) > len(sb) else -1
            if sa != sb:
                return 1 if sa > sb else -1
        else:
            if seg_a != seg_b:
                return 1 if seg_a > seg_b else -1
        i, j = pi, pj
    if i >= la and j >= lb:
        return 0
    one0 = a[i] if i < la else ""
    two0 = b[j] if j < lb else ""
    if (i >= la and not (two0.isalpha() if two0 else False)) or (
        one0.isalpha() if one0 else False
    ):
        return -1
    return 1


def vercmp(va, vb):
    """Compare full pkgver-pkgrel strings (no epoch in our filenames)."""
    pkgver_a, _, rel_a = va.rpartition("-")
    pkgver_b, _, rel_b = vb.rpartition("-")
    c = _vercmp_segment(pkgver_a, pkgver_b)
    if c != 0:
        return c
    return _vercmp_segment(rel_a, rel_b)


def parse_pkg(filename):
    """Return (pkgname, arch, version) or None if not a package file.

    Arch package filename: <name>-<pkgver>-<pkgrel>-<arch>.pkg.tar.*
    pkgver/pkgrel cannot contain '-', so rsplit from the right is exact;
    <name> itself may contain '-' (e.g. posthogos-welcome-debug).
    """
    suffix = next((s for s in PKG_SUFFIXES if filename.endswith(s)), None)
    if suffix is None:
        return None
    stem = filename[: -len(suffix)]
    parts = stem.rsplit("-", 3)
    if len(parts) != 4:
        return None
    name, pkgver, pkgrel, arch = parts
    return name, arch, f"{pkgver}-{pkgrel}"


def prune(directory, keep, dry_run):
    groups = defaultdict(list)  # (name, arch) -> [(version, filename)]
    for entry in os.listdir(directory):
        parsed = parse_pkg(entry)
        if parsed is None:
            continue
        name, arch, version = parsed
        groups[(name, arch)].append((version, entry))

    removed = []
    for (name, arch), items in sorted(groups.items()):
        # Sort newest first.
        items.sort(key=functools.cmp_to_key(lambda x, y: vercmp(y[0], x[0])))
        for version, filename in items[keep:]:
            removed.append(filename)
            sig = filename + ".sig"
            if os.path.exists(os.path.join(directory, sig)):
                removed.append(sig)

    if not removed:
        print(f"Nothing to prune in {directory} (keep={keep}).")
        return removed

    verb = "Would remove" if dry_run else "Removing"
    print(f"{verb} {len(removed)} file(s) from {directory} (keep={keep}):")
    for filename in sorted(removed):
        print(f"  {filename}")
        if not dry_run:
            os.remove(os.path.join(directory, filename))
    return removed


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("directory", help="pacman repo directory to prune")
    ap.add_argument(
        "--keep",
        type=int,
        default=2,
        help="number of newest versions to keep per package (default: 2)",
    )
    ap.add_argument(
        "--dry-run",
        action="store_true",
        help="list what would be removed without deleting",
    )
    args = ap.parse_args()
    if not os.path.isdir(args.directory):
        sys.exit(f"error: not a directory: {args.directory}")
    if args.keep < 1:
        sys.exit("error: --keep must be >= 1")
    prune(args.directory, args.keep, args.dry_run)


if __name__ == "__main__":
    main()
