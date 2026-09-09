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
phone/bash_profile:.bash_profile
phone/omarchy/shell.json:.config/omarchy/shell.json
phone/omarchy/shell.toml:.config/omarchy/shell.toml
phone/plugins/fajita.keyboard/manifest.json:.config/omarchy/plugins/fajita.keyboard/manifest.json
phone/plugins/fajita.keyboard/BarWidget.qml:.config/omarchy/plugins/fajita.keyboard/BarWidget.qml
phone/waybar/config.jsonc:.config/waybar/config.jsonc
phone/waybar/style.css:.config/waybar/style.css
phone/squeekboard.service:.config/systemd/user/squeekboard.service
phone/waybar.service:.config/systemd/user/waybar.service
phone/fajita-osk-start:.local/bin/fajita-osk-start
phone/fajita-osk-primer:.local/bin/fajita-osk-primer
phone/fajita-osk-toggle:.local/bin/fajita-osk-toggle
phone/fajita-second-bar:.local/bin/fajita-second-bar
phone/hooks/post-boot:.config/omarchy/hooks/post-boot
phone/apply-shell-patches.sh:.local/bin/apply-shell-patches.sh
phone/fajita-bar-order:.local/bin/fajita-bar-order
phone/fajita-omarchy-update:.local/bin/fajita-omarchy-update
phone/fajita-reboot-bootloader:.local/bin/fajita-reboot-bootloader
phone/bar-order.service:.config/systemd/user/bar-order.service
phone/omarchy-update.service:.config/systemd/user/omarchy-update.service
phone/omarchy-update.timer:.config/systemd/user/omarchy-update.timer
phone/omarchy-menu.jsonc:.config/omarchy/extensions/omarchy-menu.jsonc
omarchy-packages.txt:.local/share/fajita/omarchy-packages.txt
repack-noarch.sh:.local/bin/repack-noarch.sh
"

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
same=0; diff_n=0; missing=0

while IFS=: read -r repo remote; do
  [ -z "$repo" ] && continue
  local_f="$HERE/$repo"
  if ! scp -q "$PH:$remote" "$tmp/f" 2>/dev/null; then
    echo "MISSING ON PHONE  $remote"; missing=$((missing+1)); continue
  fi
  if [ ! -f "$local_f" ]; then
    echo "MISSING IN REPO   $repo"; missing=$((missing+1))
    [ "$PULL" = "--pull" ] && mkdir -p "$(dirname "$local_f")" && cp "$tmp/f" "$local_f" && echo "  pulled"
    continue
  fi
  if diff -q "$local_f" "$tmp/f" >/dev/null 2>&1; then
    same=$((same+1))
  else
    echo "DIFFERS           $repo"
    diff -u "$local_f" "$tmp/f" | sed -n '4,12p' | sed 's/^/    /'
    diff_n=$((diff_n+1))
    [ "$PULL" = "--pull" ] && cp "$tmp/f" "$local_f" && echo "    pulled phone version"
  fi
done <<< "$MAP"

# root-owned files, fetched separately
for pair in "phone/ttfx:/usr/local/bin/ttfx" "phone/proxy.sh:/etc/profile.d/proxy.sh" "phone/50-fajita-power.rules:/etc/polkit-1/rules.d/50-fajita-power.rules"; do
  repo=${pair%%:*}; remote=${pair#*:}
  if ssh "$PH" "sudo -n cat $remote" > "$tmp/f" 2>/dev/null; then   # root-owned, some in root-only dirs
    if diff -q "$HERE/$repo" "$tmp/f" >/dev/null 2>&1; then same=$((same+1)); else
      echo "DIFFERS           $repo"; diff_n=$((diff_n+1))
      [ "$PULL" = "--pull" ] && cp "$tmp/f" "$HERE/$repo" && echo "    pulled phone version"
    fi
  else
    echo "MISSING ON PHONE  $remote"; missing=$((missing+1))
  fi
done

echo
echo "$same in sync, $diff_n differ, $missing missing"
[ $((diff_n+missing)) -eq 0 ] && echo "repo matches the phone"
