#!/bin/bash
# Build q6voiced (voice-call audio daemon) as a static-ish aarch64 binary.
#
# q6voiced listens on the system DBus for ModemManager call-state signals and
# opens/closes the VoiceMMode1 hostless PCM so call audio flows; the card's
# UCM "Voice Call" verb handles the backend routing (earpiece + bottom mic).
# Upstream: https://gitlab.com/postmarketOS/q6voiced (MIT). No Arch/ALARM
# package exists and tinyalsa is AUR-only, so both are vendored into the
# build container and only libc/libdbus are linked dynamically (both already
# on the phone).
#
# Output: build/q6voiced/q6voiced — deploy to /usr/local/bin on the phone
# together with phone/q6voiced.service and /etc/conf.d/q6voiced.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../config.env"

OUT="$HERE/../build/q6voiced"
mkdir -p "$OUT"

docker run --rm -i \
  -v "$OUT:/out" \
  --platform linux/arm64 \
  debian:bookworm bash -eu -c '
    apt-get update -qq && apt-get install -qqy --no-install-recommends \
      gcc libc6-dev make git libdbus-1-dev ca-certificates >/dev/null
    git clone -q --depth 1 https://gitlab.com/postmarketOS/q6voiced /q6voiced
    git clone -q --depth 1 https://github.com/tinyalsa/tinyalsa /tinyalsa
    gcc -O2 -Wall -static-libgcc \
      -I/tinyalsa/include \
      /q6voiced/q6voiced.c /tinyalsa/src/*.c \
      -o /out/q6voiced -ldbus-1 $(pkg-config --cflags --libs dbus-1)
    /out/q6voiced 2>&1 | head -1 || true
    ls -la /out/q6voiced
  '
echo "built: $OUT/q6voiced"
