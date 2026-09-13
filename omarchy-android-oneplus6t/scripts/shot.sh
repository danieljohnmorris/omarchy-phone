#!/bin/bash
# Screenshot the phone's Hyprland session over USB: scripts/shot.sh [out.png]
source "$(dirname "$0")/../config.env"
OUT=${1:-/tmp/fajita-shot.png}
# Pull the shot through the ssh pipe, not scp: scp needs the sftp subsystem
# (absent in some rootfs builds) and a bracketed v6 target; the pipe needs
# neither. See README "Access".
ssh "$PHONE_SSH" 'export XDG_RUNTIME_DIR=/run/user/$(id -u); export WAYLAND_DISPLAY=$(ls $XDG_RUNTIME_DIR | grep -E "^wayland-[0-9]+$" | head -1); grim /tmp/shot.png' \
  && ssh "$PHONE_SSH" cat /tmp/shot.png > "$OUT" && echo "$OUT"
