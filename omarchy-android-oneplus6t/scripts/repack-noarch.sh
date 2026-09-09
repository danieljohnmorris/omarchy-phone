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
# Usage: scripts/repack-noarch.sh <pkg.tar.zst> [more...]
# Writes <name>-<ver>-any.pkg.tar.zst next to each input.
set -euo pipefail

for pkg in "$@"; do
  [ -f "$pkg" ] || { echo "no such file: $pkg" >&2; exit 1; }
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
  tar -xf "$pkg" -C "$tmp"

  elf=$(find "$tmp" -type f -exec file {} + 2>/dev/null | grep -c ELF || true)
  if [ "$elf" -ne 0 ]; then
    echo "REFUSING $(basename "$pkg"): contains $elf compiled binaries, it is genuinely x86_64" >&2
    find "$tmp" -type f -exec file {} + 2>/dev/null | grep ELF | head -5 >&2
    rm -rf "$tmp"; continue
  fi

  sed -i.bak 's/^arch = .*/arch = any/' "$tmp/.PKGINFO" && rm -f "$tmp/.PKGINFO.bak"
  out="${pkg%-*.pkg.tar.zst}-any.pkg.tar.zst"
  ( cd "$tmp" && tar --zstd -cf "$out" .PKGINFO .MTREE .INSTALL * 2>/dev/null \
    || tar --zstd -cf "$out" .PKGINFO * )
  echo "repacked $(basename "$pkg") -> $(basename "$out") ($(find "$tmp" -type f | wc -l | tr -d ' ') files, no binaries)"
  rm -rf "$tmp"; trap - EXIT
done
