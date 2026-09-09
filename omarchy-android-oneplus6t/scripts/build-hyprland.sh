#!/bin/bash
# Rebuild Hyprland from the Arch PKGBUILD inside the mounted rootfs chroot,
# because ALARM's binary hyprland lags aquamarine (soname mismatch).
# Run in the build container with /work/out/rootfs.img mounted at /mnt/rootfs.
set -euo pipefail
MNT=/mnt/rootfs
mountpoint -q $MNT || mount -o loop /work/out/rootfs.img $MNT
cp /etc/resolv.conf $MNT/etc/resolv.conf

cat > $MNT/root/hypr-build.sh <<'EOF'
set -euo pipefail
pacman -S --noconfirm --needed base-devel cmake meson ninja git \
  hyprwayland-scanner hyprutils hyprlang hyprcursor hyprgraphics aquamarine hyprwire hyprland-guiutils \
  glslang lcms2 libdrm libinput libxkbcommon muparser re2 tomlplusplus xorg-xwayland \
  xcb-util xcb-util-errors xcb-util-image xcb-util-keysyms xcb-util-renderutil xcb-util-wm \
  wayland-protocols cairo pango pixman lua >/dev/null
# builder user with pacman rights
id -u builder >/dev/null 2>&1 || useradd -m builder
echo "builder ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/builder
sudo -u builder bash -c '
  set -euo pipefail
  cd ~ && rm -rf hyprland && mkdir hyprland && cd hyprland
  curl -sfL -o PKGBUILD "https://gitlab.archlinux.org/archlinux/packaging/packages/hyprland/-/raw/main/PKGBUILD"
  grep -E "^(pkgver|pkgrel|_commit|depends|makedepends)" PKGBUILD | head -8
  MAKEFLAGS="-j$(nproc)" makepkg -A --skippgpcheck --noconfirm -s --nocheck 2>&1 | grep -vE "^\s*(--|::|\(|  )" | tail -25
  ls -la *.pkg.tar.*
'
pacman -U --noconfirm /home/builder/hyprland/hyprland-*.pkg.tar.* >/dev/null
pacman -Q hyprland
Hyprland --version 2>/dev/null | head -2 || true
mkdir -p /work-pkgs && cp /home/builder/hyprland/*.pkg.tar.* /work-pkgs/ 2>/dev/null || true
rm -rf /home/builder/hyprland/src /home/builder/hyprland/pkg
EOF
mkdir -p /work/pkgs
mount --bind /work/pkgs $MNT/work-pkgs 2>/dev/null || { mkdir -p $MNT/work-pkgs; mount --bind /work/pkgs $MNT/work-pkgs; }
arch-chroot $MNT bash /root/hypr-build.sh
umount $MNT/work-pkgs || true
rm -f $MNT/root/hypr-build.sh
echo "hyprland build done; pkg saved to /work/pkgs"; ls -la /work/pkgs
