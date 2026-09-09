#!/bin/bash
# Build pd-mapper + tqftpserv (Qualcomm modem/WLAN firmware services, not in
# ALARM repos) from source inside the mounted rootfs chroot and enable them.
# Without pd-mapper the WCN3990 Wi-Fi never appears (wlan0 depends on it).
# Run in the build container with /work/out/rootfs.img mounted at /mnt/rootfs.
set -euo pipefail
MNT=/mnt/rootfs
mountpoint -q $MNT || mount -o loop /work/out/rootfs.img $MNT
cp /etc/resolv.conf $MNT/etc/resolv.conf

# arch-chroot mounts a tmpfs on /tmp, so build under /root
cat > $MNT/root/qcom-build.sh <<'EOF'
set -euo pipefail
pacman -S --noconfirm --needed meson ninja pkgconf git base-devel >/dev/null
rm -rf /root/q && mkdir -p /root/q && cd /root/q
git clone -q --depth 1 https://github.com/linux-msm/tqftpserv.git
( cd tqftpserv && meson setup build --prefix=/usr >/dev/null && ninja -C build >/dev/null && ninja -C build install >/dev/null )
git clone -q --depth 1 https://github.com/linux-msm/pd-mapper.git
( cd pd-mapper && make -j"$(nproc)" >/dev/null && make install prefix=/usr >/dev/null )
systemctl enable pd-mapper tqftpserv rmtfs >/dev/null 2>&1
# ALSA UCM profiles for the OnePlus 6T sound card ("O6T"): upstream alsa-ucm-conf
# only ships DB845c/Lenovo for sdm845, so PipeWire sees a dummy sink without these.
git clone -q --depth 1 https://gitlab.com/sdm845-mainline/alsa-ucm-conf.git
cp -a alsa-ucm-conf/ucm2/. /usr/share/alsa/ucm2/
rm -rf /root/q
ls -la /usr/bin/pd-mapper /usr/bin/tqftpserv
EOF
arch-chroot $MNT bash /root/qcom-build.sh
rm -f $MNT/root/qcom-build.sh
echo "qcom services built + enabled"
