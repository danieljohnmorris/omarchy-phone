#!/bin/bash
# Runs inside the Arch ARM chroot (arch-chroot). Env: USER_NAME USER_PASS HOSTNAME_ KVER
set -euo pipefail

echo "$HOSTNAME_" > /etc/hostname
ln -sf "/usr/share/zoneinfo/${PHONE_TZ:-Europe/London}" /etc/localtime
LOC=${PHONE_LOCALE:-en_GB.UTF-8}
sed -i "s/^#${LOC}/${LOC}/; s/^#en_US.UTF-8/en_US.UTF-8/" /etc/locale.gen
locale-gen >/dev/null
echo "LANG=$LOC" > /etc/locale.conf

pacman-key --init >/dev/null 2>&1
pacman-key --populate archlinuxarm >/dev/null 2>&1

# drop ALARM generic kernel; we ship the pmOS sdm845 kernel out-of-band
pacman -Rns --noconfirm linux-aarch64 2>/dev/null || true
# core: must succeed
pacman -Syu --noconfirm --needed \
  base sudo openssh networkmanager iwd wireless-regdb \
  mkinitcpio kmod zstd util-linux linux-firmware-qcom \
  seatd polkit git vim htop 2>&1 | tail -3

# optional: install one by one so a missing package doesn't kill the build
OPTIONAL="modemmanager bluez bluez-utils pipewire pipewire-pulse wireplumber alsa-ucm-conf alsa-utils
  qrtr rmtfs pd-mapper tqftpserv
  hyprland foot waybar wofi swaybg xdg-desktop-portal-hyprland hyprpaper
  squeekboard mesa vulkan-freedreno
  base-devel fastfetch chromium
  ttf-jetbrains-mono-nerd noto-fonts noto-fonts-emoji"
MISSING=""
for p in $OPTIONAL; do
  pacman -S --noconfirm --needed "$p" >/dev/null 2>&1 || MISSING="$MISSING $p"
done
echo "optional packages missing:${MISSING:- none}"

# user
useradd -m -G wheel,video,input,seat,audio -s /bin/bash "$USER_NAME" 2>/dev/null || true
echo "$USER_NAME:$USER_PASS" | chpasswd
echo "root:$USER_PASS" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
# ALARM default user
userdel -r alarm 2>/dev/null || true

# ssh: allow password for first contact; key later
sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication yes/; s/^#\?PermitRootLogin .*/PermitRootLogin yes/' /etc/ssh/sshd_config

# services
for s in sshd NetworkManager seatd usb-gadget systemd-networkd ModemManager bluetooth qrtr-ns rmtfs pd-mapper tqftpserv; do
  systemctl enable "$s" >/dev/null 2>&1 || echo "no unit: $s"
done

# NetworkManager uses iwd backend (better on qcom wifi)
mkdir -p /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/wifi-backend.conf <<EOF
[device]
wifi.backend=iwd
EOF

# modules: depmod for the pmOS kernel
depmod -a "$KVER"

# initramfs: no autodetect (host kernel != target), all block/phy drivers in
install -m644 /root/mkinitcpio.conf /etc/mkinitcpio.conf && rm -f /root/mkinitcpio.conf
echo "KEYMAP=uk" > /etc/vconsole.conf
mkinitcpio -k "$KVER" -g /boot/initramfs-"$KVER".img 2>&1 | grep -Ev "^\s*->" | tail -5
ls -la /boot/initramfs-"$KVER".img

# clean
pacman -Scc --noconfirm >/dev/null 2>&1 || true
rm -rf /var/cache/pacman/pkg/* /root/.bash_history
echo "chroot setup ok"
