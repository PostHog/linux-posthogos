#!/usr/bin/env python3
"""Prune superseded .deb packages from an apt repo's pool/.

Keeps the N newest versions of each (package, arch) and deletes older .deb
files. The Packages index (regenerated from the current build on each
release) only ever lists the latest version, so older pool/ files are
orphans that just consume the Pages quota — this is the apt analogue of
prune-pacman-repo.py.

Walks the given directory recursively for *.deb (our pool layout is
pool/main/p/<pkg>/<pkg>_<ver>_<arch>.deb). No detached signatures to clean
up (apt signs the Release, not individual debs).

No external dependencies (no dpkg): version ordering is a faithful port of
dpkg's verrevcmp (lib/dpkg/version.c), including epoch, the upstream/revision
split, and '~' (which sorts before everything, even end-of-string).
"""

import argparse
import functools
import os
import sys
from collections import defaultdict


def _order(c):
    """dpkg order(): '~' < end-of-string < digit-run < letters < other punct."""
    if c == "":
        return 0
    if c.isdigit():
        return 0
    if c.isalpha():
        return ord(c)
    if c == "~":
        return -1
    return ord(c) + 256


def _verrevcmp(a, b):
    """Port of dpkg verrevcmp() for one component (upstream or revision)."""
    a = a or ""
    b = b or ""
    ia, ib = 0, 0
    la, lb = len(a), len(b)
    while ia < la or ib < lb:
        # Non-digit run: compare char by char via order(); past end reads as "".
        while (ia < la and not a[ia].isdigit()) or (ib < lb and not b[ib].isdigit()):
            ac = _order(a[ia]) if ia < la else 0
            bc = _order(b[ib]) if ib < lb else 0
            if ac != bc:
                return ac - bc
            if ia < la:
                ia += 1
            if ib < lb:
                ib += 1
        # Strip leading zeros, then compare the digit runs.
        while ia < la and a[ia] == "0":
            ia += 1
        while ib < lb and b[ib] == "0":
            ib += 1
        first_diff = 0
        while ia < la and a[ia].isdigit() and ib < lb and b[ib].isdigit():
            if first_diff == 0:
                first_diff = ord(a[ia]) - ord(b[ib])
            ia += 1
            ib += 1
        if ia < la and a[ia].isdigit():
            return 1  # a has a longer digit run => larger
        if ib < lb and b[ib].isdigit():
            return -1
        if first_diff:
            return first_diff
    return 0


def _split(v):
    """Split a Debian version into (epoch:int, upstream:str, revision:str)."""
    epoch = 0
    rest = v
    if ":" in v:
        head, _, rest = v.partition(":")
        if head.isdigit():
            epoch = int(head)
    if "-" in rest:
        upstream, _, revision = rest.rpartition("-")
    else:
        upstream, revision = rest, ""
    return epoch, upstream, revision


def deb_vercmp(va, vb):
    """Compare two Debian version strings → -1 / 0 / 1."""
    ea, ua, ra = _split(va)
    eb, ub, rb = _split(vb)
    if ea != eb:
        return -1 if ea < eb else 1
    c = _verrevcmp(ua, ub)
    if c:
        return -1 if c < 0 else 1
    c = _verrevcmp(ra, rb)
    return -1 if c < 0 else (1 if c > 0 else 0)


def parse_deb(filename):
    """Return (package, arch, version) or None.

    Debian binary filename: <package>_<version>_<arch>.deb. Package names
    never contain '_' and our versions never contain '_' (pre-release '_' is
    mapped to '~' at build time), so split('_') yields exactly three fields.
    """
    if not filename.endswith(".deb"):
        return None
    stem = filename[: -len(".deb")]
    parts = stem.split("_")
    if len(parts) != 3:
        return None
    package, version, arch = parts
    return package, arch, version


def prune(directory, keep, dry_run):
    # (name, arch) -> [(version, full_path)]
    groups = defaultdict(list)
    for root, _dirs, files in os.walk(directory):
        for entry in files:
            parsed = parse_deb(entry)
            if parsed is None:
                continue
            name, arch, version = parsed
            groups[(name, arch)].append((version, os.path.join(root, entry)))

    removed = []
    for (_name, _arch), items in sorted(groups.items()):
        # Newest first.
        items.sort(key=functools.cmp_to_key(lambda x, y: deb_vercmp(y[0], x[0])))
        for _version, path in items[keep:]:
            removed.append(path)

    if not removed:
        print(f"Nothing to prune in {directory} (keep={keep}).")
        return removed

    verb = "Would remove" if dry_run else "Removing"
    print(f"{verb} {len(removed)} file(s) from {directory} (keep={keep}):")
    for path in sorted(removed):
        print(f"  {os.path.relpath(path, directory)}")
        if not dry_run:
            os.remove(path)
    return removed


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("directory", help="apt repo dir to prune (walked for *.deb)")
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
