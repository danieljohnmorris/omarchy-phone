#!/bin/bash
# Build Arch Linux ARM rootfs image for OnePlus 6T (fajita), run INSIDE the
# privileged arm64 build container with /work mounted.
#
# Inputs (in /work):
#   ArchLinuxARM-aarch64-latest.tar.gz
#   pmos/x/linux-postmarketos-qcom-sdm845-*/   (pmOS kernel apk, extracted)
#   pmos/x/firmware-oneplus-sdm845-*/          (pmOS firmware apk, extracted)
# Output:
#   /work/out/rootfs.img   ext4, label archroot, flashed to userdata
#   /work/out/boot.img     android boot image (kernel+dtb, mkinitcpio initramfs)
set -euo pipefail

W=/work
OUT=$W/out
IMG=$OUT/rootfs.img
MNT=/mnt/rootfs
SIZE=$ROOTFS_SIZE
KVER=$(ls $W/pmos/x/linux-postmarketos-qcom-sdm845-*/lib/modules/ | head -1)   # e.g. 6.16.7-sdm845
KPKG=$(ls -d $W/pmos/x/linux-postmarketos-qcom-sdm845-*/ | head -1)
FWPKG=$(ls -d $W/pmos/x/firmware-oneplus-sdm845-[0-9]*/ | head -1)
SCRIPTS=$W/scripts
source "$W/config.env" 2>/dev/null || source "$(dirname "$0")/../config.env"
USER_NAME=$PHONE_USER
USER_PASS=$PHONE_PASS
HOSTNAME_=$PHONE_HOSTNAME

echo "kernel: $KVER  from $KPKG"
echo "firmware: $FWPKG"

mkdir -p $OUT $MNT
umount -R $MNT 2>/dev/null || true
rm -f $IMG
truncate -s $SIZE $IMG
# UFS on fajita has 4096-byte logical sectors
mkfs.ext4 -q -F -b 4096 -L archroot -O ^has_journal,^metadata_csum_seed $IMG
mount -o loop $IMG $MNT

echo "== extracting ALARM"
tar -xpf $W/ArchLinuxARM-aarch64-latest.tar.gz -C $MNT --numeric-owner

echo "== kernel + modules + firmware"
rm -rf $MNT/boot/* $MNT/usr/lib/modules/* $MNT/lib/modules/* 2>/dev/null || true
cp -a $KPKG/boot/vmlinuz $MNT/boot/vmlinuz-$KVER
mkdir -p $MNT/boot/dtbs/qcom
cp -a $KPKG/boot/dtbs/qcom/. $MNT/boot/dtbs/qcom/
test -s $MNT/boot/dtbs/qcom/sdm845-oneplus-fajita.dtb || { echo "fajita dtb missing"; exit 1; }
mkdir -p $MNT/usr/lib/modules
cp -a $KPKG/lib/modules/$KVER $MNT/usr/lib/modules/$KVER
mkdir -p $MNT/usr/lib/firmware
cp -a $FWPKG/lib/firmware/. $MNT/usr/lib/firmware/
# pmOS puts device-specific blobs under lib/firmware/postmarketos; kernel searches /lib/firmware/postmarketos too via fw_path? no - flatten them
if [ -d $FWPKG/lib/firmware/postmarketos ]; then
  cp -a $FWPKG/lib/firmware/postmarketos/. $MNT/usr/lib/firmware/
fi
chown -R 0:0 $MNT/usr/lib/firmware $MNT/usr/lib/modules $MNT/boot

echo "== host files into rootfs"
install -Dm644 $SCRIPTS/rootfs/mkinitcpio.conf      $MNT/root/mkinitcpio.conf   # applied after pacman in chroot-setup
install -Dm644 $SCRIPTS/rootfs/initcpio/fajitaroot.hook    $MNT/etc/initcpio/hooks/fajitaroot
install -Dm644 $SCRIPTS/rootfs/initcpio/fajitaroot.install $MNT/etc/initcpio/install/fajitaroot
install -Dm644 $SCRIPTS/rootfs/usb-gadget.service   $MNT/etc/systemd/system/usb-gadget.service
install -Dm755 $SCRIPTS/rootfs/usb-gadget.sh        $MNT/usr/local/bin/usb-gadget.sh
install -Dm644 $SCRIPTS/rootfs/10-usb0.network      $MNT/etc/systemd/network/10-usb0.network
install -Dm644 $SCRIPTS/rootfs/99-fajita.conf       $MNT/etc/NetworkManager/conf.d/99-fajita.conf
install -Dm755 $SCRIPTS/rootfs/chroot-setup.sh      $MNT/root/chroot-setup.sh
rm -f $MNT/etc/resolv.conf; cp /etc/resolv.conf $MNT/etc/resolv.conf

echo "== chroot setup"
USER_NAME=$USER_NAME USER_PASS=$USER_PASS HOSTNAME_=$HOSTNAME_ KVER=$KVER \
  arch-chroot $MNT /root/chroot-setup.sh

rm -f $MNT/root/chroot-setup.sh
# ALARM ships resolv.conf as a symlink target handled by NM/resolved; leave stub
echo "nameserver 1.1.1.1" > $MNT/etc/resolv.conf

echo "== hyprland rebuild (ALARM binary lags aquamarine) + qcom services"
bash $SCRIPTS/build-hyprland.sh
bash $SCRIPTS/build-qcom-services.sh
mountpoint -q $MNT || mount -o loop $IMG $MNT
# passwordless sudo for the phone user (no keyboard on device; everything is driven over ssh)
echo "$USER_NAME ALL=(ALL) NOPASSWD: ALL" > $MNT/etc/sudoers.d/$USER_NAME; chmod 440 $MNT/etc/sudoers.d/$USER_NAME

echo "== boot.img"
DTB=$MNT/boot/dtbs/qcom/sdm845-oneplus-fajita.dtb
cat $MNT/boot/vmlinuz-$KVER $DTB > $OUT/kernel-dtb
cp $MNT/boot/initramfs-$KVER.img $OUT/initramfs.img
mkbootimg \
  --kernel $OUT/kernel-dtb \
  --ramdisk $OUT/initramfs.img \
  --base 0x00000000 --pagesize 4096 \
  --kernel_offset 0x00008000 --ramdisk_offset 0x01000000 \
  --second_offset 0x00f00000 --tags_offset 0x00000100 \
  --cmdline "console=ttyMSM0,115200 console=tty0 fbcon=rotate:1 root=/dev/sda17 rootfstype=ext4 rw rootwait loglevel=7 systemd.show_status=1 initcall_blacklist=simplefb_init" \
  -o $OUT/boot.img

sync
umount -R $MNT
e2fsck -fy $IMG >/dev/null || true
# sparse image: fastboot only transfers used blocks (raw 16G takes ~10 min over USB2)
img2simg $IMG $OUT/rootfs.simg 4096 && echo "sparse: $(du -h $OUT/rootfs.simg | cut -f1)"
echo "== done"
ls -la $OUT
