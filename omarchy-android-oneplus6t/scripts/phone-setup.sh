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
scp -q "$HERE/phone/monitors.lua" "$HERE/phone/input.lua" "$HERE/phone/autostart.lua" "$HERE/phone/looknfeel.lua" "$HERE/phone/bindings.lua" $PH:/tmp/
scp -q "$HERE/phone/bash_profile" $PH:/tmp/bash_profile
scp -q "$HERE/phone/hooks/post-boot" $PH:/tmp/post-boot
scp -q "$HERE/phone/hooks/theme-set.d/fajita-theme-rows" $PH:/tmp/fajita-theme-rows
ssh $PH 'cp -rn /etc/skel/. ~/; cp /etc/skel/.bashrc ~/.bashrc
  source /etc/profile.d/omarchy.sh; source /etc/profile.d/proxy.sh
  OMARCHY_SETUP_CONTEXT=provision omarchy-provision-user --force || true
  cp /tmp/monitors.lua /tmp/input.lua /tmp/autostart.lua /tmp/looknfeel.lua /tmp/bindings.lua ~/.config/hypr/
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
  install -Dm755 /tmp/fajita-theme-rows ~/.config/omarchy/hooks/theme-set.d/fajita-theme-rows
  sudo systemctl enable sshd'

echo "== keyboard toggle bar widget (squeekboard auto-show is unreliable on Hyprland)"
ssh $PH 'mkdir -p ~/.config/omarchy/plugins/fajita.keyboard ~/.config/omarchy/plugins/fajita.cellular ~/.local/bin'
scp -q "$HERE/phone/plugins/fajita.keyboard/manifest.json" "$HERE/phone/plugins/fajita.keyboard/BarWidget.qml" $PH:~/.config/omarchy/plugins/fajita.keyboard/
ssh $PH 'mkdir -p ~/.config/omarchy/plugins/fajita.close'
scp -q "$HERE/phone/plugins/fajita.close/manifest.json" "$HERE/phone/plugins/fajita.close/BarWidget.qml" $PH:~/.config/omarchy/plugins/fajita.close/
scp -q "$HERE/phone/plugins/fajita.cellular/manifest.json" "$HERE/phone/plugins/fajita.cellular/BarWidget.qml" "$HERE/phone/plugins/fajita.cellular/Panel.qml" $PH:~/.config/omarchy/plugins/fajita.cellular/
scp -q "$HERE/phone/fajita-osk-toggle" "$HERE/phone/fajita-osk-start" "$HERE/phone/fajita-osk-fit" "$HERE/phone/fajita-slot-ok" "$HERE/phone/fajita-screen-off" "$HERE/phone/fajita-power-key" "$HERE/phone/fajita-cell-status" "$HERE/phone/fajita-cell-toggle" "$HERE/phone/fajita-cell-info" "$HERE/phone/fajita-cell-reconnect" "$HERE/phone/fajita-lock-screen" $PH:~/.local/bin/
# gum is a shim, not a fajita-* script, and it goes to /usr/local/bin because
# ~/.local/bin sits AFTER /usr/bin in the phone's PATH (a shim there is dead
# code). It routes confirm and single-select choose to the touch-driven
# Quickshell menu, because gum emits no mouse-enable sequence at all and its
# Yes/No cannot be tapped in a terminal.
ssh $PH 'cat > /tmp/gum' < "$HERE/phone/gum"
ssh $PH 'sudo install -m755 /tmp/gum /usr/local/bin/gum'

# Theme previews upstream are 1800x1012 desktop screenshots, unreadable at 540
# wide and not what changes on a phone. This shim builds the preview set from
# each theme's first wallpaper instead. /usr/local/bin, ahead of /usr/bin, and
# the menu runs actions under `bash -lc` so the login PATH reaches it.
ssh $PH 'cat > /tmp/omarchy-theme-switcher' < "$HERE/phone/omarchy-theme-switcher"
ssh $PH 'sudo install -m755 /tmp/omarchy-theme-switcher /usr/local/bin/omarchy-theme-switcher'
scp -q "$HERE/phone/squeekboard.service" "$HERE/phone/osk-fit.service" "$HERE/phone/empty-hint.service" $PH:~/.config/systemd/user/
scp -q "$HERE/phone/fajita-osk-theme" $PH:~/.local/bin/
ssh $PH 'chmod +x ~/.local/bin/fajita-osk-theme && ~/.local/bin/fajita-osk-theme'

# An empty workspace draws nothing on a tiling compositor and there is no
# keyboard to press SUPER+RETURN with, so it looks exactly like a dead phone.
# A standalone Quickshell process draws the empty state and a tappable
# launcher. Standalone, not a plugin under /usr/share/omarchy, so a pacman
# upgrade cannot overwrite it and apply-shell-patches.sh need not know about it.
ssh $PH 'mkdir -p ~/.config/fajita'
scp -q "$HERE/phone/empty-hint.qml" $PH:.config/fajita/empty-hint.qml
# Phone lock screen, notification center, quick settings: standalone Quickshell
# surfaces under ~/.config/fajita for the same pacman-proof reason as the hint.
scp -q "$HERE/phone/lock.qml" "$HERE/phone/notif.qml" "$HERE/phone/quicksettings.qml" "$HERE/phone/calls.qml" $PH:.config/fajita/
ssh $PH 'chmod +x ~/.local/bin/fajita-osk-toggle ~/.local/bin/fajita-osk-start ~/.local/bin/fajita-osk-fit ~/.local/bin/fajita-slot-ok ~/.local/bin/fajita-screen-off ~/.local/bin/fajita-power-key ~/.local/bin/fajita-cell-status ~/.local/bin/fajita-cell-toggle ~/.local/bin/fajita-cell-info ~/.local/bin/fajita-cell-reconnect ~/.local/bin/fajita-lock-screen
  # squeekboard must bind while a focused text client exists (Hyprland 0.56 IME relay quirk); the
  # service primes that with a throwaway terminal. Do NOT start it from Hyprland exec/autostart.lua.
  # osk-fit unfloats floating windows while the keyboard is up so they are not covered by it.
  systemctl --user daemon-reload; systemctl --user enable squeekboard.service osk-fit.service empty-hint.service'

# The bar layout (keyboard toggle on the right, clock moved to row two) and the
# text size ship as captured files rather than being edited in place.
ssh $PH 'mkdir -p ~/.config/omarchy'
scp -q "$HERE/phone/omarchy/shell.json" "$HERE/phone/omarchy/shell.toml" $PH:.config/omarchy/
ssh $PH 'sudo systemctl restart getty@tty1'

# Chromium's first launch asks gcr-prompter to create a keyring, an unanswerable
# two-password dialog on a device with no keyboard. The flags file uses
# --password-store=basic instead; see the comment in it.
scp -q "$HERE/phone/chromium-flags.conf" $PH:.config/chromium-flags.conf

# GTK's text-scaling-factor must stay 1.0: Chromium sizes its Wayland buffer as
# logical x text-scale and Hyprland crops the excess, so any other value cuts
# web pages off on the right. Readability comes from Chromium's own page zoom
# instead, which scales layout and cannot clip. The bar and terminals are
# unaffected either way: they read shell.toml [font] base-size and their own
# point sizes, not this factor. `omarchy display text size N` rewrites the
# factor, so re-run this block after using it.
ssh $PH 'export XDG_RUNTIME_DIR=/run/user/1001
  gsettings set org.gnome.desktop.interface text-scaling-factor 1.0 || true
  pkill -x chromium 2>/dev/null; sleep 2
  prefs=~/.config/chromium/Default/Preferences
  [ -f "$prefs" ] && python3 -c "
import json,math,sys
p=sys.argv[1]
d=json.load(open(p))
d.setdefault(\"partition\",{})[\"default_zoom_level\"]={\"0\":math.log(1.35)/math.log(1.2)}
json.dump(d,open(p,\"w\"))" "$prefs" || true'

echo "== phone housekeeping: Arch maintenance jobs peg this CPU for minutes after boot"
ssh $PH 'sudo systemctl mask man-db.timer man-db.service plocate-updatedb.timer plocate-updatedb.service shadow.timer archlinux-keyring-wkd-sync.timer >/dev/null 2>&1 || true
  # suspend never resumes on fajita (s2idle freezes userspace with no wake path)
  sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target >/dev/null 2>&1 || true
  sudo mkdir -p /etc/systemd/logind.conf.d
  printf "[Login]\nIdleAction=ignore\nHandleLidSwitch=ignore\nHandleSuspendKey=ignore\n" | sudo tee /etc/systemd/logind.conf.d/10-fajita-nosuspend.conf >/dev/null'

echo "== screensaver effects engine (Omarchy ships ttfx for x86_64 only)"
# Real Rust binary, committed for parity. Rebuild with build-ttfx.sh (needs
# Docker on any host; arm64 container runs natively on Apple Silicon).
# Never fall back to a Python shim: tte at 120fps saturates SDM845 and wedges
# the session, and omarchy-screensaver's respawn loop multiplies it.
if [ ! -x "$HERE/phone/ttfx-aarch64" ]; then
  echo "phone/ttfx-aarch64 missing; building via build-ttfx.sh"
  "$HERE/build-ttfx.sh"
fi
scp -q "$HERE/phone/ttfx-aarch64" $PH:/tmp/ttfx-aarch64
ssh $PH 'sudo install -m755 /tmp/ttfx-aarch64 /usr/local/bin/ttfx
  # verify before trusting: must run and exit, not hang
  timeout 10 /usr/local/bin/ttfx --version || echo "WARN: ttfx --version rc=$?"
  timeout 5 /usr/local/bin/ttfx -i ~/.config/omarchy/branding/screensaver.txt --random-effect --no-eol </dev/null >/dev/null 2>&1 || true'


echo "== second bar row: clock under Omarchy's bar (the notch blocks the centre of row one)"
ssh $PH 'mkdir -p ~/.config/waybar ~/.config/systemd/user ~/.local/bin'
scp -q "$HERE/phone/waybar/config.jsonc" $PH:.config/waybar/
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

echo "== voice calls + SMS: q6voiced (call audio), helpers, apps, watcher"
# q6voiced is upstream postmarketOS C (MIT); build-q6voiced.sh cross-builds it
# in a debian:bookworm arm64 container. Committed under phone/ so a setup run
# needs no Docker, same as the screensaver binary.
if [ ! -x "$HERE/phone/q6voiced" ]; then
  "$HERE/build-q6voiced.sh"
  install -m755 "$HERE/../build/q6voiced/q6voiced" "$HERE/phone/q6voiced"
fi
scp -q "$HERE/phone/q6voiced" "$HERE/phone/q6voiced.service" $PH:/tmp/
ssh $PH 'sudo install -m755 -o root -g root /tmp/q6voiced /usr/local/bin/q6voiced
  sudo install -m644 -o root -g root /tmp/q6voiced.service /etc/systemd/system/q6voiced.service
  sudo systemctl daemon-reload; sudo systemctl enable --now q6voiced.service'

# 81voltd answers the modem's QMI IMS Data requests, which brings the `ims` APN
# bearer up. Without it a VoLTE-only network has no route to this device and
# inbound SMS never arrives; with it the operator delivers queued messages.
if [ ! -x "$HERE/phone/81voltd" ]; then
  "$HERE/build-81voltd.sh"
  install -m755 "$HERE/../build/81voltd/81voltd" "$HERE/phone/81voltd"
fi
# fajita-ims-wait is the unit's ExecStartPost: 81voltd answers the modem's
# single IMS request with no retry, so the unit must verify the bearer and fail
# if it is absent, letting Restart=always try again (see the unit's comment).
scp -q "$HERE/phone/81voltd" "$HERE/phone/81voltd.service" "$HERE/phone/fajita-ims-wait" $PH:/tmp/
ssh $PH 'sudo install -m755 -o root -g root /tmp/81voltd /usr/local/bin/81voltd
  sudo install -m755 -o root -g root /tmp/fajita-ims-wait /usr/local/bin/fajita-ims-wait
  sudo install -m644 -o root -g root /tmp/81voltd.service /etc/systemd/system/81voltd.service
  sudo systemctl daemon-reload; sudo systemctl enable --now 81voltd.service'

# Call/SMS control from a seatless caller (ssh, systemd --user) needs polkit:
# without this every mmcli voice/messaging op fails Unauthorized.
scp -q "$HERE/phone/51-fajita-modem.rules" $PH:/tmp/
ssh $PH 'sudo install -m644 -o root -g root /tmp/51-fajita-modem.rules /etc/polkit-1/rules.d/51-fajita-modem.rules
  sudo systemctl restart polkit'

# ~/.local/share/applications exists on a phone that already has the Omarchy
# webapp entries, but not necessarily on a from-scratch run, and scp will not
# create it.
ssh $PH 'mkdir -p ~/.local/bin ~/.config/fajita ~/.config/systemd/user ~/.local/share/applications ~/.local/state/fajita'
scp -q "$HERE/phone/fajita-call" "$HERE/phone/fajita-sms" "$HERE/phone/fajita-call-watch" $PH:.local/bin/
scp -q "$HERE/phone/calls.qml" "$HERE/phone/messages.qml" $PH:.config/fajita/
scp -q "$HERE/phone/fajita-call-watch.service" $PH:.config/systemd/user/
# Desktop entries so both apps appear in the Apps menu ("launch something" on
# the empty-workspace hint, or the bar icon), not only in the power-key menu.
scp -q "$HERE/phone/calls.desktop" "$HERE/phone/messages.desktop" $PH:.local/share/applications/
ssh $PH 'chmod +x ~/.local/bin/fajita-call ~/.local/bin/fajita-sms ~/.local/bin/fajita-call-watch
  mkdir -p ~/.local/state/fajita
  systemctl --user daemon-reload
  systemctl --user enable --now fajita-call-watch.service'

echo "phone setup done"
