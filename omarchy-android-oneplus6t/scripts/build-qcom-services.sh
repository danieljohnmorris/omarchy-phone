#!/bin/bash
# Build the Qualcomm modem stack (qrtr, rmtfs, pd-mapper, tqftpserv — none are in
# the ALARM repos) from source inside the mounted rootfs chroot and enable them.
# Without pd-mapper the WCN3990 Wi-Fi never appears (wlan0 depends on it).
# Without rmtfs the modem subsystem cannot touch its EFS partitions at all.
#
# Versions: qrtr/rmtfs are pinned to the exact commits validated on the phone
# (2026-09-12; the live image runs qrtr r126.ae88108 / rmtfs r78.14cb1ee);
# pd-mapper/tqftpserv track linux-msm heads like before. alsa-ucm-conf is
# pinned to 1b8d290 (2026-05-09), the tree the deployed md5s in
# fajita-call-audio-diag were computed from: unpinned, any upstream change
# would make this check false-alarm after a rebuild.
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
git clone -q https://github.com/linux-msm/qrtr.git
( cd qrtr && git checkout -q ae88108 && meson setup build --prefix=/usr >/dev/null && ninja -C build >/dev/null && ninja -C build install >/dev/null )
git clone -q --depth 1 https://github.com/linux-msm/tqftpserv.git
( cd tqftpserv && meson setup build --prefix=/usr >/dev/null && ninja -C build >/dev/null && ninja -C build install >/dev/null )
git clone -q --depth 1 https://github.com/linux-msm/pd-mapper.git
( cd pd-mapper && make -j"$(nproc)" >/dev/null && make install prefix=/usr >/dev/null )
git clone -q https://github.com/linux-msm/rmtfs.git
( cd rmtfs && git checkout -q 14cb1ee && make -j"$(nproc)" >/dev/null && make install prefix=/usr >/dev/null )
# pmOS-parity unit: -r -P -s, exactly what pmOS ships (their confd sets
# rmtfs_avoid_writing=true) and what the validated live image runs.
# -r = avoid writing to storage, -P = use raw EFS partitions, -s = sync the
# mss remoteproc lifecycle with rmtfs.
cat > /etc/systemd/system/rmtfs.service <<'UNIT'
[Unit]
Description=Qualcomm Remote Filesystem Service
Before=ModemManager.service

[Service]
ExecStart=/usr/bin/rmtfs -r -P -s
Restart=always

[Install]
WantedBy=multi-user.target
UNIT
systemctl enable rmtfs pd-mapper tqftpserv >/dev/null 2>&1
# ALSA UCM profiles for the OnePlus 6T sound card ("O6T"): upstream alsa-ucm-conf
# only ships DB845c/Lenovo for sdm845, so PipeWire sees a dummy sink without these.
git clone -q https://gitlab.com/sdm845-mainline/alsa-ucm-conf.git
( cd alsa-ucm-conf && git checkout -q 1b8d290 )
cp -a alsa-ucm-conf/ucm2/. /usr/share/alsa/ucm2/
rm -rf /root/q
ls -la /usr/bin/qrtr-ns /usr/bin/rmtfs /usr/bin/pd-mapper /usr/bin/tqftpserv
EOF
arch-chroot $MNT bash /root/qcom-build.sh
rm -f $MNT/root/qcom-build.sh
echo "qcom services built + enabled"
