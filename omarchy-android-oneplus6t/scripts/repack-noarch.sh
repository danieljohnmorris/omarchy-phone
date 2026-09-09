#!/bin/bash
# Relabel an Omarchy package as architecture-independent, but only if it really
# is: refuse anything containing compiled code.
#
# Why this exists: Omarchy 4.0.2 shipped the core `omarchy` and `omarchy-settings`
# packages as arch=any, so they installed on aarch64. From 4.0.3 they are labelled
# x86_64, even though they still contain nothing but shell scripts, QML, Lua and
# assets (verified: 1172 files, zero ELF binaries). pacman refuses a foreign-arch
# package, so without this the phone is pinned to 4.0.2 forever.
#
# Entries are written owned by root:root. An earlier version tarred with the
# invoking user's uid, and pacman then installed /etc/sudoers.d/omarchy-tzupdate
# owned by uid 501, which sudo refuses to read.
#
# Usage: scripts/repack-noarch.sh <pkg.tar.zst> [more...]
# Writes <name>-<ver>-any.pkg.tar.zst next to each input.
set -euo pipefail

for pkg in "$@"; do
  [ -f "$pkg" ] || { echo "no such file: $pkg" >&2; exit 1; }
  tmp=$(mktemp -d)
  tar -xf "$pkg" -C "$tmp"

  elf=$(find "$tmp" -type f -exec file {} + 2>/dev/null | grep -c ELF || true)
  if [ "$elf" -ne 0 ]; then
    echo "REFUSING $(basename "$pkg"): contains $elf compiled binaries, it is genuinely x86_64" >&2
    find "$tmp" -type f -exec file {} + 2>/dev/null | grep ELF | head -5 >&2
    rm -rf "$tmp"; continue
  fi

  sed -i.bak 's/^arch = .*/arch = any/' "$tmp/.PKGINFO" && rm -f "$tmp/.PKGINFO.bak"
  out="${pkg%-*.pkg.tar.zst}-any.pkg.tar.zst"

  # Force root ownership regardless of which tar this is (GNU on the phone or
  # in Docker, bsdtar on macOS) by writing the archive from python's tarfile.
  python3 - "$tmp" "$out" <<'PY'
import io, os, subprocess, sys, tarfile
src, out = sys.argv[1], sys.argv[2]
buf = io.BytesIO()
with tarfile.open(fileobj=buf, mode="w", format=tarfile.GNU_FORMAT) as tf:
    def root(ti):
        ti.uid = ti.gid = 0; ti.uname = ti.gname = "root"; return ti
    # pacman expects the metadata files first
    for meta in (".PKGINFO", ".MTREE", ".INSTALL", ".BUILDINFO", ".CHANGELOG"):
        p = os.path.join(src, meta)
        if os.path.exists(p): tf.add(p, arcname=meta, filter=root)
    for name in sorted(os.listdir(src)):
        if name.startswith("."): continue
        tf.add(os.path.join(src, name), arcname=name, filter=root)
with open(out, "wb") as f:
    subprocess.run(["zstd", "-q", "-T0", "-c"], input=buf.getvalue(), stdout=f, check=True)
PY
  echo "repacked $(basename "$pkg") -> $(basename "$out") ($(find "$tmp" -type f | wc -l | tr -d ' ') files, no binaries, root-owned)"
  rm -rf "$tmp"
done
