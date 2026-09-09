#!/bin/bash
# Screenshot the phone's Hyprland session over USB: scripts/shot.sh [out.png]
source "$(dirname "$0")/../config.env"
OUT=${1:-/tmp/fajita-shot.png}
ssh "$PHONE_SSH" 'export XDG_RUNTIME_DIR=/run/user/$(id -u); export WAYLAND_DISPLAY=$(ls $XDG_RUNTIME_DIR | grep -E "^wayland-[0-9]+$" | head -1); grim /tmp/shot.png' && scp -q "$PHONE_SSH":/tmp/shot.png "$OUT" && echo "$OUT"
