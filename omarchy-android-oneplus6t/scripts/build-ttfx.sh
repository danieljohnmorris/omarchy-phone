#!/bin/bash
# Build ttfx (the Rust terminal-effects engine Omarchy's screensaver drives)
# for aarch64.
#
# Why: Omarchy ships ttfx as an x86_64 binary only, so on an ARM phone the
# Screensaver menu row does nothing. Upstream (github.com/omacom-io/ttfx)
# publishes no aarch64 release, so we build it. The Python
# python-terminaltexteffects fallback is too slow at 120 fps on SDM845 and
# wedges the session, which is why this build exists instead.
#
# How: Docker. On an ARM host (Apple Silicon, an ARM Linux box) the arm64
# container runs natively — that is the tested path. On an x86_64 host it
# still works but needs qemu-user-static + binfmt registered
# (`docker run --privileged --rm tonistiigi/binfmt --install arm64`), and the
# emulated Rust build takes many minutes rather than ~20 seconds.
# Debian bookworm + rustup (NOT Alpine/musl: its packaged rust cannot build
# proc-macro crates like clap_derive; and NOT Debian's apt cargo: rustc 1.63
# is below ttfx's MSRV). The glibc target (aarch64-unknown-linux-gnu) links
# against Debian's older glibc, so the binary runs on the phone's newer
# Arch glibc.
#
# Output: phone/ttfx-aarch64 — install to /usr/local/bin/ttfx on the device
# (phone-setup.sh does this; check-sync.sh tracks it).
#
# The committed phone/ttfx-aarch64 is:
#   sha256 8d93aaeea60e25b7abae4d9eab9adb885455b68770d54b3fab6e3c93188db87a
#   built with rustc 1.98.1 from tag v0.3.2
# Verify the tracked binary with `shasum -a 256 phone/ttfx-aarch64`. A rebuild
# will NOT reproduce that hash byte-for-byte: the source tag is pinned but
# rustup installs whatever rustc is current, and the build embeds a BuildID.
# Compare behaviour (`ttfx --version` reports 0.3.2), not bytes.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT="$HERE/phone/ttfx-aarch64"

docker run --rm --platform linux/arm64 \
  -v "$HERE:/out" \
  debian:bookworm-slim bash -ec '
    apt-get update -qq
    apt-get install -y -qq --no-install-recommends \
      git build-essential pkg-config curl ca-certificates
    curl -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
    . "$HOME/.cargo/env"
    cd /tmp
    git clone -q --depth 1 --branch v0.3.2 https://github.com/omacom-io/ttfx
    cd ttfx
    cargo build --release
    cp target/release/ttfx /out/phone/ttfx-aarch64
  '

file "$OUT" || true
ls -la "$OUT"
echo "built: $OUT"
echo "install on the phone: sudo install -m755 $OUT /usr/local/bin/ttfx"
