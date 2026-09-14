#!/bin/bash
# Build 81voltd (QMI IMS Data service) as an aarch64 binary.
#
# The modem firmware does the IMS/SIP work itself, but it will not register
# unless something on the host answers the QMI IMS Data service and brings up
# the dedicated IMS PDN bearer on request. On Android that is a Qualcomm vendor
# blob; 81voltd reimplements just that server side and lets ModemManager drive
# it. Without it, an LTE-only network (Three UK here) has no way to carry voice:
# no CS domain to fall back to and no IMS registration.
#
# Upstream: https://gitlab.com/flamingradian/81voltd (GPL-2.0-or-later),
# packaged by postmarketOS in pmaports/temp/81voltd. Reported working on some
# sdm845 devices (Pixel 3a / Optus) and not on others, so treat a build as
# necessary-but-not-sufficient: the carrier's IMS profile decides.
#
# Deps: mm-glib (ModemManager) and libqrtr. Debian ships neither header set at
# a useful version, so qrtr is built from linux-msm source in the container --
# the same upstream build-qcom-services.sh pins for the device's own qrtr.
# The binary links dynamically; the phone already has libqrtr.so.1,
# libmm-glib.so.0 and glib 2.88 (build-old/run-new is fine, both ABIs are
# additive).
#
# Ships together with phone/81voltd.service.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../config.env"

OUT="$HERE/../build/81voltd"
mkdir -p "$OUT"

docker run --rm -i \
  -v "$OUT:/out" \
  --platform linux/arm64 \
  debian:bookworm bash -eu -c '
    apt-get update -qq && apt-get install -qqy --no-install-recommends \
      gcc libc6-dev meson ninja-build pkg-config git ca-certificates \
      libglib2.0-dev libmm-glib-dev >/dev/null

    # qrtr: headers + shared lib the daemon links against.
    git clone -q --depth 1 https://github.com/linux-msm/qrtr /qrtr
    meson setup /qrtr/build /qrtr >/dev/null
    meson install -C /qrtr/build >/dev/null

    git clone -q --depth 1 https://gitlab.com/flamingradian/81voltd /81voltd
    cd /81voltd
    # qmic is absent, so meson copies the pre-generated QMI stubs instead of
    # regenerating them from imsd.qmi. That is the upstream fallback path.
    meson setup build . >/dev/null
    meson compile -C build >/dev/null
    cp build/81voltd /out/81voltd
    ldd /out/81voltd || true
    ls -la /out/81voltd
  '
echo "built: $OUT/81voltd"
