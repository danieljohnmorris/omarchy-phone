# omarchy-phone

I put [Omarchy](https://omarchy.org) on a OnePlus 6T. It boots Arch Linux ARM
with a mainline kernel instead of Android, then Hyprland, then Omarchy's own
shell on top of that. Android's system partitions are still on the device; only
a boot slot and the data partition are overwritten.

There's a folder per device with the build scripts, the config that lands on the
phone, and the patches that make a desktop shell work with a finger.

## Devices

| Folder | Device | Where it got to |
|---|---|---|
| [`omarchy-android-oneplus6t`](omarchy-android-oneplus6t) | OnePlus 6T (fajita), Snapdragon 845 | Boots on its own into Omarchy 4. Bar, menu, on-screen keyboard, terminal, GPU, audio, Wi-Fi all work. Bluetooth, lock screen and cellular don't. |

## Omarchy on ARM

Omarchy publishes x86_64 builds only. There is an aarch64 repo at
`pkgs.omarchy.org/aarch64` but it holds one package, and DHH has said ARM support
is coming.

When I counted, at 4.0.3, the x86_64 repo held 217 packages and 33 were
`arch=any`. Ten of those are what the phone installs: the shell, the menus, the
Neovim config, the fonts and the icon theme. The rest are labelled x86_64.

Some are labelled x86_64 without containing any compiled code. Omarchy 4.0.2
shipped `omarchy` and `omarchy-settings` as `arch=any`; 4.0.3 labels them x86_64,
and I unpacked it to check: 1172 files, no binaries at all. `repack-noarch.sh`
relabels packages like that, and refuses any that really do contain binaries.

## What took the time

Very little of it was the build. Three things came up repeatedly, and I'd expect
all three on any phone.

- **Touch.** Handlers written for a mouse ignore a finger, so menus opened but
  nothing selected. Popups sized for a laptop cover the screen. The panel's
  click-catcher counted the first tap on the on-screen keyboard as a click
  outside itself and closed.
- **Anything compiled is missing.** The screensaver needs `ttfx`, a Rust rewrite
  Omarchy builds for x86_64. I swapped in the Python original it was ported from.
  It runs, but not at 120fps: at Omarchy's default it saturated the CPU and hung
  the phone.
- **Phone hardware.** The notch sits where the clock goes, so the time was
  unreadable until I moved it to a second bar row. Suspend never resumes, which
  looks exactly like a dead phone. There's no real-time clock, so every boot
  starts in 1970, and anything that picks the newest file by timestamp quietly
  chooses a stale one.

Each folder writes up what it hit and why it happened.

## Licence

MIT.
