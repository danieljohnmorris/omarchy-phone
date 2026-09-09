#!/bin/bash
# Apply the Omarchy layer + phone adaptations to a booted fajita over USB ssh.
#
# Assumes: rootfs from build-rootfs.sh is running, `ssh $PHONE_SSH` works
# (key installed), and the Mac has `ssh -N -R 1080 $PHONE_SSH` running
# (reverse SOCKS so the phone reaches the internet through the Mac, no Mac sudo).
#
# OPK: directory of arch=any packages fetched from https://pkgs.omarchy.org/x86_64
#      (omarchy, omarchy-keyring, omarchy-settings, omarchy-nvim, tobi-try,
#       ttf-ia-writer, ttf-jetbrains-mono-nerd-basic, xdg-terminal-exec, yaru-icon-theme)
set -euo pipefail
source "$(dirname "$0")/../config.env"
PH=$PHONE_SSH
HERE="$(cd "$(dirname "$0")" && pwd)"
OPK=${OPK:-$HERE/../work/opkgs}

echo "== proxy, pacman sandbox, clock"
scp -q "$HERE/phone/proxy.sh" $PH:/tmp/proxy.sh
ssh $PH "sudo install -m644 /tmp/proxy.sh /etc/profile.d/proxy.sh"
ssh $PH "sudo timedatectl set-ntp true; sudo timedatectl set-timezone $PHONE_TZ"
ssh $PH 'grep -q "^DisableSandbox" /etc/pacman.conf || sudo sed -i "s/^\[options\]/[options]\nDisableSandbox/" /etc/pacman.conf
  source /etc/profile.d/proxy.sh; sudo -E pacman -Sy --noconfirm >/dev/null'

echo "== phone package set"
L=$(grep -vE "^#" "$HERE/phone-packages.txt" | tr '\n' ' ' | sed 's/localsend //; s/walker //')
ssh $PH "source /etc/profile.d/proxy.sh; sudo -E pacman -S --noconfirm --needed $L uwsm"

echo "== omarchy packages, laptop-only deps skipped: limine sddm snapper plymouth"
# Fetch/repack first if the cache is empty. Omarchy has no ARM builds yet (its
# aarch64 repo exists but holds only omarchy-keyring), so this takes the
# architecture-independent packages plus any x86_64-labelled ones that contain
# no compiled code, relabelled by repack-noarch.sh.
[ -n "$(ls -A "$OPK" 2>/dev/null)" ] || "$HERE/fetch-packages.sh"
scp -q "$OPK"/*.pkg.tar.zst $PH:/tmp/
ssh $PH 'sudo pacman -Rdd --noconfirm ttf-jetbrains-mono-nerd >/dev/null 2>&1 || true
  sudo pacman -Udd --noconfirm /tmp/*.pkg.tar.zst'

echo "== user provisioning + phone overrides"
scp -q "$HERE/phone/monitors.lua" "$HERE/phone/input.lua" "$HERE/phone/autostart.lua" "$HERE/phone/looknfeel.lua" $PH:/tmp/
scp -q "$HERE/phone/bash_profile" $PH:/tmp/bash_profile
scp -q "$HERE/phone/hooks/post-boot" $PH:/tmp/post-boot
ssh $PH 'cp -rn /etc/skel/. ~/; cp /etc/skel/.bashrc ~/.bashrc
  source /etc/profile.d/omarchy.sh; source /etc/profile.d/proxy.sh
  OMARCHY_SETUP_CONTEXT=provision omarchy-provision-user --force || true
  cp /tmp/monitors.lua /tmp/input.lua /tmp/autostart.lua /tmp/looknfeel.lua ~/.config/hypr/
  cp /tmp/bash_profile ~/.bash_profile
  # no fcitx5 on the phone; its restart loop steals Hyprland single input-method slot from squeekboard
  systemctl --user mask omarchy-fcitx5.service 2>/dev/null || true
  # cannot type a lock password without the OSK: never idle-lock
  omarchy-toggle-idle stay-awake || true
  # squeekboard only auto-shows on text focus with this on (Hyprland exposes virtual keyboards)
  gsettings set org.gnome.desktop.a11y.applications screen-keyboard-enabled true || true
  # Omarchy migration 1788124236 disables sshd on first session start unless it
  # finds an authorized key; the phone is driven over USB ssh, so mark that
  # migration done and re-enable sshd from a post-boot hook regardless.
  mkdir -p ~/.local/state/omarchy/migrations ~/.config/omarchy/hooks
  touch ~/.local/state/omarchy/migrations/1788124236
  # Migration 1787215483 calls mise, which is not packaged for aarch64, and a
  # failed migration blocks every later one and reopens the update prompt on
  # each login. Mark it done; the preinstalls-removed marker makes the other
  # mise-based migrations (Hermes, Cursor, Muse wrappers) skip themselves.
  touch ~/.local/state/omarchy/migrations/1787215483.sh ~/.local/state/omarchy/preinstalls-removed
  install -m755 /tmp/post-boot ~/.config/omarchy/hooks/post-boot
  sudo systemctl enable sshd'

echo "== keyboard toggle bar widget (squeekboard auto-show is unreliable on Hyprland)"
ssh $PH 'mkdir -p ~/.config/omarchy/plugins/fajita.keyboard ~/.local/bin'
scp -q "$HERE/phone/plugins/fajita.keyboard/manifest.json" "$HERE/phone/plugins/fajita.keyboard/BarWidget.qml" $PH:~/.config/omarchy/plugins/fajita.keyboard/
scp -q "$HERE/phone/fajita-osk-toggle" "$HERE/phone/fajita-osk-start" "$HERE/phone/fajita-slot-ok" $PH:~/.local/bin/
scp -q "$HERE/phone/squeekboard.service" $PH:~/.config/systemd/user/
ssh $PH 'chmod +x ~/.local/bin/fajita-osk-toggle ~/.local/bin/fajita-osk-start ~/.local/bin/fajita-slot-ok
  # squeekboard must bind while a focused text client exists (Hyprland 0.56 IME relay quirk); the
  # service primes that with a throwaway terminal. Do NOT start it from Hyprland exec/autostart.lua.
  systemctl --user daemon-reload; systemctl --user enable squeekboard.service'

# The bar layout (keyboard toggle on the right, clock moved to row two) and the
# text size ship as captured files rather than being edited in place.
ssh $PH 'mkdir -p ~/.config/omarchy'
scp -q "$HERE/phone/omarchy/shell.json" "$HERE/phone/omarchy/shell.toml" $PH:.config/omarchy/
ssh $PH 'sudo systemctl restart getty@tty1'

echo "== phone housekeeping: Arch maintenance jobs peg this CPU for minutes after boot"
ssh $PH 'sudo systemctl mask man-db.timer man-db.service plocate-updatedb.timer plocate-updatedb.service shadow.timer archlinux-keyring-wkd-sync.timer >/dev/null 2>&1 || true
  # suspend never resumes on fajita (s2idle freezes userspace with no wake path)
  sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target >/dev/null 2>&1 || true
  sudo mkdir -p /etc/systemd/logind.conf.d
  printf "[Login]\nIdleAction=ignore\nHandleLidSwitch=ignore\nHandleSuspendKey=ignore\n" | sudo tee /etc/systemd/logind.conf.d/10-fajita-nosuspend.conf >/dev/null'

echo "== screensaver effects engine (Omarchy ships ttfx for x86_64 only)"
scp -q "$HERE/phone/ttfx" $PH:/tmp/ttfx
ssh $PH 'sudo install -m755 /tmp/ttfx /usr/local/bin/ttfx'


echo "== second bar row: clock under Omarchy's bar (the notch blocks the centre of row one)"
ssh $PH 'mkdir -p ~/.config/waybar ~/.config/systemd/user ~/.local/bin'
scp -q "$HERE/phone/waybar/config.jsonc" "$HERE/phone/waybar/style.css" $PH:.config/waybar/
scp -q "$HERE/phone/fajita-second-bar" $PH:.local/bin/
scp -q "$HERE/phone/waybar.service" $PH:.config/systemd/user/
ssh $PH 'chmod +x ~/.local/bin/fajita-second-bar
  systemctl --user daemon-reload; systemctl --user enable waybar.service
  # bigger type: Omarchy defaults are laptop-sized and unreadable on a 6.4in panel
  omarchy-display-text-size 18 >/dev/null 2>&1 || true'



echo "== keep the clock row under Omarchy's bar across shell restarts, and weekly Omarchy upgrades"
scp -q "$HERE/phone/fajita-bar-order" "$HERE/phone/fajita-omarchy-update" "$HERE/repack-noarch.sh" $PH:.local/bin/
scp -q "$HERE/phone/bar-order.service" "$HERE/phone/omarchy-update.service" "$HERE/phone/omarchy-update.timer" $PH:.config/systemd/user/
ssh $PH 'mkdir -p ~/.local/share/fajita'
scp -q "$HERE/omarchy-packages.txt" $PH:.local/share/fajita/
ssh $PH 'chmod +x ~/.local/bin/fajita-bar-order ~/.local/bin/fajita-omarchy-update ~/.local/bin/repack-noarch.sh
  systemctl --user daemon-reload
  systemctl --user enable bar-order.service omarchy-update.timer'


echo "== reboot/shutdown from the menu without a polkit password prompt"
scp -q "$HERE/phone/50-fajita-power.rules" $PH:/tmp/
ssh $PH 'sudo install -m644 -o root -g root /tmp/50-fajita-power.rules /etc/polkit-1/rules.d/50-fajita-power.rules; sudo systemctl restart polkit'


echo "== menu extension: Reboot to bootloader (replaces the three-button hold)"
scp -q "$HERE/phone/fajita-reboot-bootloader" $PH:.local/bin/
ssh $PH 'mkdir -p ~/.config/omarchy/extensions; chmod +x ~/.local/bin/fajita-reboot-bootloader'
scp -q "$HERE/phone/omarchy-menu.jsonc" $PH:.config/omarchy/extensions/omarchy-menu.jsonc

echo "phone setup done"
