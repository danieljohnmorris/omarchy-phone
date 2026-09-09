#!/bin/bash
# Re-apply the phone patches to Omarchy's shipped Quickshell shell.
# Run on the phone after any omarchy package upgrade (pacman overwrites /usr/share/omarchy).
set -euo pipefail
P=/usr/share/omarchy/shell/Ui/KeyboardPanel.qml
sudo cp -n "$P" "$P.orig" 2>/dev/null || true
sudo python3 - "$P" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
old="""  mask: Region {
    width: root.screenW
    height: root.screenH
  }"""
new="""  mask: Region {
    width: root.screenW
    height: root.screenH
    // Phone port: the on-screen keyboard shares this overlay layer, so a tap on
    // a key counts as an outside click and closes the panel before anything is
    // typed. Subtract the keyboard strip so taps reach squeekboard instead.
    regions: [
      Region {
        x: 0
        y: root.screenH - 315
        width: root.screenW
        height: 315
        intersection: Intersection.Subtract
      }
    ]
  }"""
if new.split("\n")[3] in s:
    print("already patched"); sys.exit(0)
assert old in s, "anchor not found; upstream KeyboardPanel.qml changed"
open(p,"w").write(s.replace(old,new,1)); print("patched")
PY
# 2) Menu rows: pointer-only handlers ignore finger taps on a layer surface.
M=/usr/share/omarchy/shell/plugins/menu/Menu.qml
sudo cp -n "$M" "$M.orig" 2>/dev/null || true
sudo python3 - "$M" <<'PY2'
import sys
p=sys.argv[1]; s=open(p).read()
if "acceptedDevices: PointerDevice.TouchScreen" in s:
    print("menu already patched"); sys.exit(0)
old="""                onClicked: {
                  root.cursorActive = true
                  root.selectedIndex = row.index
                  root.activateIndex(row.index, true)
                }
              }"""
new=old+"""

              // Phone port: the MouseArea above only sees pointer events, and a
              // finger tap on this layer surface never synthesizes one, so the
              // menu could not be used by touch. Handle the touchscreen here.
              TapHandler {
                acceptedDevices: PointerDevice.TouchScreen
                gesturePolicy: TapHandler.ReleaseWithinBounds
                onTapped: {
                  root.cursorActive = true
                  root.selectedIndex = row.index
                  root.activateIndex(row.index, true)
                }
              }"""
assert old in s, "menu anchor not found; upstream Menu.qml changed"
open(p,"w").write(s.replace(old,new,1)); print("patched menu")
PY2

omarchy-restart-shell >/dev/null 2>&1 || true
echo "shell restarted"
