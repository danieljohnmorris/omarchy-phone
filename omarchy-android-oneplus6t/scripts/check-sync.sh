#!/bin/bash
# Compare every file this repo ships against the live phone, in both directions.
# Run it after changing anything on the device, so nothing lives only there.
# Usage: scripts/check-sync.sh [--pull]   (--pull copies the phone's version back)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../config.env"
PH=$PHONE_SSH
PULL=${1:-}

# repo path : phone path
MAP="
phone/monitors.lua:.config/hypr/monitors.lua
phone/input.lua:.config/hypr/input.lua
phone/autostart.lua:.config/hypr/autostart.lua
phone/hyprland.lua:.config/hypr/hyprland.lua
phone/looknfeel.lua:.config/hypr/looknfeel.lua
phone/bindings.lua:.config/hypr/bindings.lua
phone/bash_profile:.bash_profile
phone/omarchy/shell.json:.config/omarchy/shell.json
phone/omarchy/shell.toml:.config/omarchy/shell.toml
phone/plugins/fajita.keyboard/manifest.json:.config/omarchy/plugins/fajita.keyboard/manifest.json
phone/plugins/fajita.keyboard/BarWidget.qml:.config/omarchy/plugins/fajita.keyboard/BarWidget.qml
phone/waybar/config.jsonc:.config/waybar/config.jsonc
phone/squeekboard.service:.config/systemd/user/squeekboard.service
phone/osk-fit.service:.config/systemd/user/osk-fit.service
phone/waybar.service:.config/systemd/user/waybar.service
phone/fajita-osk-start:.local/bin/fajita-osk-start
phone/fajita-osk-primer:.local/bin/fajita-osk-primer
phone/fajita-osk-toggle:.local/bin/fajita-osk-toggle
phone/fajita-osk-fit:.local/bin/fajita-osk-fit
phone/fajita-slot-ok:.local/bin/fajita-slot-ok
phone/fajita-screen-off:.local/bin/fajita-screen-off
phone/fajita-power-key:.local/bin/fajita-power-key
phone/fajita-second-bar:.local/bin/fajita-second-bar
phone/hooks/post-boot:.config/omarchy/hooks/post-boot
phone/hooks/theme-set.d/fajita-theme-rows:.config/omarchy/hooks/theme-set.d/fajita-theme-rows
phone/apply-shell-patches.sh:.local/bin/apply-shell-patches.sh
phone/fajita-bar-order:.local/bin/fajita-bar-order
phone/fajita-omarchy-update:.local/bin/fajita-omarchy-update
phone/fajita-reboot-bootloader:.local/bin/fajita-reboot-bootloader
phone/bar-order.service:.config/systemd/user/bar-order.service
phone/omarchy-update.service:.config/systemd/user/omarchy-update.service
phone/omarchy-update.timer:.config/systemd/user/omarchy-update.timer
phone/omarchy-menu.jsonc:.config/omarchy/extensions/omarchy-menu.jsonc
phone/chromium-flags.conf:.config/chromium-flags.conf
phone/chromium-ua-mobile/manifest.json:.config/chromium/extensions/ua-mobile/manifest.json
phone/chromium-ua-mobile/ua.js:.config/chromium/extensions/ua-mobile/ua.js
phone/empty-hint.service:.config/systemd/user/empty-hint.service
phone/empty-hint.qml:.config/fajita/empty-hint.qml
phone/plugins/fajita.close/manifest.json:.config/omarchy/plugins/fajita.close/manifest.json
phone/plugins/fajita.close/BarWidget.qml:.config/omarchy/plugins/fajita.close/BarWidget.qml
phone/notif.qml:.config/fajita/notif.qml
phone/quicksettings.qml:.config/fajita/quicksettings.qml
phone/lock.qml:.config/fajita/lock.qml
phone/fajita-lock-screen:.local/bin/fajita-lock-screen
omarchy-packages.txt:.local/share/fajita/omarchy-packages.txt
repack-noarch.sh:.local/bin/repack-noarch.sh
"

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
same=0; diff_n=0; missing=0

# One connection for everything: rapid per-file ssh legs stall the USB
# gadget's link-local stack (first fetches start erroring "interrupted").
REMOTES=""
while IFS=: read -r repo remote; do
  [ -z "$repo" ] && continue
  REMOTES="$REMOTES $remote"
done <<< "$MAP"
if ! ssh -o ConnectTimeout=8 "$PH" "cd ~ && tar -cf - $REMOTES 2>/dev/null" | tar -xf - -C "$tmp"; then
  echo "PHONE UNREACHABLE — nothing compared"; exit 1
fi

while IFS=: read -r repo remote; do
  [ -z "$repo" ] && continue
  local_f="$HERE/$repo"
  if [ ! -f "$tmp/$remote" ]; then
    echo "MISSING ON PHONE  $remote"; missing=$((missing+1))
    continue
  fi
  if [ ! -f "$local_f" ]; then
    echo "MISSING IN REPO   $repo"; missing=$((missing+1))
    [ "$PULL" = "--pull" ] && mkdir -p "$(dirname "$local_f")" && cp "$tmp/$remote" "$local_f" && echo "  pulled"
    continue
  fi
  if diff -q "$local_f" "$tmp/$remote" >/dev/null 2>&1; then
    same=$((same+1))
  else
    echo "DIFFERS           $repo"
    diff -u "$local_f" "$tmp/$remote" | sed -n '4,12p' | sed 's/^/    /'
    diff_n=$((diff_n+1))
    [ "$PULL" = "--pull" ] && cp "$tmp/$remote" "$local_f" && echo "    pulled phone version"
  fi
done <<< "$MAP"

# root-owned files, fetched separately
for pair in "phone/ttfx:/usr/local/bin/ttfx" "phone/gum:/usr/local/bin/gum" "phone/omarchy-theme-switcher:/usr/local/bin/omarchy-theme-switcher" "phone/proxy.sh:/etc/profile.d/proxy.sh" "phone/50-fajita-power.rules:/etc/polkit-1/rules.d/50-fajita-power.rules"; do
  repo=${pair%%:*}; remote=${pair#*:}
  if ssh -o ConnectTimeout=8 "$PH" "sudo -n tar -cf - $remote 2>/dev/null" | tar -xf - -C "$tmp" 2>/dev/null && [ -f "$tmp$remote" ]; then
    if diff -q "$HERE/$repo" "$tmp$remote" >/dev/null 2>&1; then same=$((same+1)); else
      echo "DIFFERS           $repo"; diff_n=$((diff_n+1))
      [ "$PULL" = "--pull" ] && cp "$tmp$remote" "$HERE/$repo" && echo "    pulled phone version"
    fi
  else
    echo "MISSING ON PHONE  $remote"; missing=$((missing+1))
  fi
done

echo
echo "$same in sync, $diff_n differ, $missing missing"
[ $((diff_n+missing)) -eq 0 ] && echo "repo matches the phone"
