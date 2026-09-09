# Omarchy ports

Getting [Omarchy](https://omarchy.org) running on hardware it was not built for.
One folder per device, each self-contained: build scripts, the configuration that
lands on the device, and the patches needed to make a desktop shell usable there.

Omarchy publishes x86_64 builds only. Its aarch64 repository exists but currently
holds a single package, and DHH has said ARM support is coming. Until then, a
third of its packages are architecture-independent and install anywhere; the rest
are compiled for Intel. Where a package is labelled x86_64 but contains no
compiled code, `repack-noarch.sh` relabels it, refusing anything with real
binaries.

## Devices

| Folder | Device | State |
|---|---|---|
| [`omarchy-android-oneplus6t`](omarchy-android-oneplus6t) | OnePlus 6T (fajita), Snapdragon 845 | Boots unattended into Omarchy 4. Bar, menu, on-screen keyboard, terminal, GPU, audio, Wi-Fi. Bluetooth, lock screen and cellular outstanding. |

## What these ports have in common

Android is replaced entirely: the phone runs Arch Linux ARM with a mainline
kernel, Hyprland, and Omarchy's own shell on top. Nothing here forks Omarchy or
Arch; each folder is the recipe that assembles them, so upstream stays upstream.

The recurring work is not the build, it is the assumptions a desktop makes:

- **Touch.** Handlers written for a mouse ignore a finger. Popups sized for a
  laptop cover a phone screen. A dismiss-on-outside-click surface swallows the
  first keypress on an on-screen keyboard.
- **Architecture.** Anything compiled is missing, and the substitutes are slower.
- **Phone hardware.** Notches sit where clocks go. Suspend does not always
  resume. There is no real-time clock, so the machine starts in 1970 and things
  that sort by time silently pick the wrong one.

Each device folder documents what it hit, with the reasoning, so the next port
starts further along.

## Licence

MIT. See each folder's `LICENSE`.
