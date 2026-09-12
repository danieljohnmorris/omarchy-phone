#!/bin/bash
# Build ModemManager from git (pinned) with our patches inside the mounted
# rootfs chroot, replacing the distro binary.
#
# Why: Arch ARM ships MM 1.24.2, which crash-loops (SIGSEGV) on this device
# the moment a muxed (qmapmux) data connection is set up — use-after-free in
# the netlink transaction layer, fixed in mm-patches/. pmOS runs a newer MM
# (1.25.95-git) that only carries the same upstream bug; our patch applies to
# both. DMS SHUTTING_DOWN handling (needed by this modem firmware) is already
#  in the pinned commit upstream (31cbf9c1 — committed after being found on a
#  OnePlus 6T with postmarketOS).
#
SCRIPTS_DIR=$(cd "$(dirname "$0")" && pwd)
#
# Run in the build container with /work/out/rootfs.img mounted at /mnt/rootfs.
set -euo pipefail
MNT=/mnt/rootfs
MM_COMMIT=d776ea38d29ca472a12323c1d45002ee19a66f57   # MM 1.25.95-git, 2026-07-09
mountpoint -q $MNT || mount -o loop /work/out/rootfs.img $MNT
cp /etc/resolv.conf $MNT/etc/resolv.conf

# arch-chroot mounts a tmpfs on /tmp, so build under /root
cat > $MNT/root/mm-build.sh <<EOF
set -euo pipefail
# gdbus-codegen lives in the glib2 split package on ALARM
pacman -S --noconfirm --needed git meson ninja pkgconf glib2-devel >/dev/null
rm -rf /root/mm && mkdir -p /root/mm && cd /root/mm
git clone -q https://gitlab.freedesktop.org/mobile-broadband/ModemManager.git
cd ModemManager && git checkout -q $MM_COMMIT
for p in /root/mm-patches/*.patch; do git apply --check "\$p"; done
for p in /root/mm-patches/*.patch; do git apply "\$p"; done
meson setup build --prefix=/usr -Dintrospection=false -Dpolkit=permissive -Dtests=false >/dev/null
ninja -C build >/dev/null
ninja -C build install >/dev/null
cd / && rm -rf /root/mm
/usr/bin/ModemManager --version
EOF
mkdir -p $MNT/root/mm-patches
cp "$SCRIPTS_DIR/mm-patches/"*.patch $MNT/root/mm-patches/
arch-chroot $MNT bash /root/mm-build.sh
rm -rf $MNT/root/mm-patches $MNT/root/mm-build.sh
echo "ModemManager built + installed"
