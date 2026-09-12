#!/bin/bash
# Screenshot the phone's Hyprland session over USB: scripts/shot.sh [out.png]
source "$(dirname "$0")/../config.env"
OUT=${1:-/tmp/fajita-shot.png}
# macOS ssh takes a link-local v6 host bare (user@fe80::…%en16) but scp needs it
# bracketed (user@[fe80::…%en16]); derive the scp form from PHONE_SSH.
case "${PHONE_SSH#*@}" in
  *:*) SCP_TARGET="${PHONE_SSH%%@*}@[${PHONE_SSH#*@}]" ;;
  *)   SCP_TARGET="$PHONE_SSH" ;;
esac
ssh "$PHONE_SSH" 'export XDG_RUNTIME_DIR=/run/user/$(id -u); export WAYLAND_DISPLAY=$(ls $XDG_RUNTIME_DIR | grep -E "^wayland-[0-9]+$" | head -1); grim /tmp/shot.png' && scp -q "$SCP_TARGET:/tmp/shot.png" "$OUT" && echo "$OUT"
