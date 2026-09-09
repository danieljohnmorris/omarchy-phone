#!/bin/bash
# Mac side: unlock + flash OnePlus 6T (fajita) with the images from work/out.
# Usage: scripts/flash.sh unlock | flash | boot-test
set -euo pipefail
PT=~/Library/Android/sdk/platform-tools
ADB=$PT/adb; FB=$PT/fastboot
source "$(dirname "$0")/../config.env"
OUT="$(cd "$(dirname "$0")/.." && pwd)/work/out"

to_bootloader() {
  if $FB devices | grep -q fastboot; then return; fi
  if $ADB get-state 2>/dev/null | grep -q device; then
    echo "-> adb reboot bootloader"; $ADB reboot bootloader
  else
    echo "-> no adb device; hold Power+VolUp+VolDown until fastboot"; fi
  echo "-> waiting for fastboot"; until $FB devices | grep -q fastboot; do sleep 1; done
  $FB devices
}

case "${1:-}" in
  unlock)
    to_bootloader
    echo "-> unlock status:"; $FB oem device-info 2>&1 | grep -iE "unlock|verity" || true
    echo "-> fastboot oem unlock  (CONFIRM ON PHONE: VolUp to select UNLOCK THE BOOTLOADER, Power to confirm; WIPES DATA)"
    $FB oem unlock || $FB flashing unlock
    echo "-> phone will wipe + reboot to Android once (takes a few min). Re-enable USB debugging is NOT needed for fastboot."
    ;;
  boot-test)
    # try the kernel without flashing anything (fastboot boot). Rootfs must already be on userdata.
    to_bootloader
    $FB boot "$OUT/boot.img"
    ;;
  flash)
    to_bootloader
    ls -la "$OUT/boot.img" "$OUT/rootfs.img"
    echo "-> current slot: $($FB getvar current-slot 2>&1 | grep -i slot || true)"
    echo "-> erase dtbo (android dtbo overlay conflicts with mainline dtb)"
    $FB erase dtbo || true
    echo "-> flash boot"
    $FB flash boot "$OUT/boot.img"
    echo "-> flash userdata (rootfs)"
    if [ -f "$OUT/rootfs.simg" ]; then $FB -S 512M flash userdata "$OUT/rootfs.simg"
    else $FB -S 512M flash userdata "$OUT/rootfs.img"; fi
    echo "-> reboot"
    $FB reboot
    echo "-> after ~30s a new USB ethernet interface appears on the Mac; phone is $PHONE_IP"
    echo "   ssh $PHONE_SSH   (password: $PHONE_PASS)"
    ;;
  *) echo "usage: $0 unlock|flash|boot-test"; exit 1;;
esac
