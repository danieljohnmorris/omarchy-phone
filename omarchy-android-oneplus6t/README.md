# Omarchy on a OnePlus 6T (fajita)

Pure Arch Linux ARM + Hyprland 0.56 + Omarchy 4.0.2 Quattro replacing Android
on a OnePlus 6T. Kernel is the prebuilt postmarketOS `linux-postmarketos-qcom-sdm845`
6.16.7 binary with the fajita DTB; everything else is Arch, built with pacman.

Nothing here forks Omarchy or Arch. It is the recipe that assembles them for a
phone: image build scripts, the device configuration that lands on the phone,
and a small set of patches to Omarchy's touch behaviour, kept re-appliable
because package upgrades overwrite them. See Status at the bottom for what
works.

## Layout

- `scripts/build-rootfs.sh` — run inside the privileged arm64 Docker container
  (`fajita-build`, `work/` mounted at `/work`). Produces `work/out/rootfs.img`
  (16 GB ext4, label `archroot`) and `work/out/boot.img`.
- `scripts/rootfs/` — files dropped into the image: mkinitcpio config, the
  `fajitaroot` initcpio hook, USB gadget service, networkd config.
- `scripts/build-hyprland.sh` — rebuilds Hyprland from the Arch PKGBUILD inside
  the chroot (ALARM's binary lags aquamarine's soname).
- `scripts/build-qcom-services.sh` — pd-mapper, tqftpserv (linux-msm GitHub) and
  the sdm845-mainline ALSA UCM profiles. Wi-Fi does not appear without pd-mapper.
- `scripts/flash.sh` — host side: `unlock | boot-test | flash` via fastboot.
- `scripts/phone-setup.sh` — Omarchy layer + phone adaptations over ssh.
- `scripts/phone/` — the phone-side files (Lua overrides, bash_profile, proxy env, hooks).
- `scripts/shot.sh` — screenshot the phone's Hyprland session over USB.
- `work/` (gitignored) — tarballs, pmOS apks, images, Omarchy checkout, packages.

## Hard-won facts

- **Fastboot on a Mac needs a USB 2.0-only cable** (a charge cable). USB 3
  cables enumerate for adb but the bootloader's USB stack drops off silently.
- The OnePlus bootloader appends `root=/dev/dm-0 dm=...` after our cmdline.
  `PARTLABEL=userdata` and `/dev/sda17` both time out unless the initramfs
  hook `fajitaroot` forces the root device. maggu2810 hit the same thing.
- Booting from the flashed boot partition (not `fastboot boot`) hands the kernel
  a splash `simplefb` that steals fb0 and blanks the panel:
  `initcall_blacklist=simplefb_init`. Test on flashed boots, not `fastboot boot`.
- The Adreno 630 probes before the rootfs mounts: its firmware must be in the
  initramfs (`FILES=` in mkinitcpio.conf).
- The command-mode panel garbles fbcon unless `fbcon=rotate:1`.
- Key combos: fastboot = from off with cable OUT, Power+VolUp+VolDown, release
  Power at the vibrate, keep the volumes until "FastBoot Mode". Both volumes
  with the cable IN = EDL (9008). Exit EDL: unplug, VolUp+Power 20 s.
- Once Linux runs, the boot partition can be rewritten over ssh:
  `dd if=boot.img of=/dev/disk/by-partlabel/boot_b`. No more key dance.
- pacman 7's Landlock sandbox fails on this kernel: `DisableSandbox` in pacman.conf.
- No RTC: enable NTP (`timedatectl set-ntp true`) or set the date over ssh.
- Omarchy migration `1788124236` disables sshd at first session start if it
  thinks no key is authorized. It did, and locked the host out. `phone-setup.sh`
  now marks it done, a `post-boot` hook re-enables sshd, and an `ensuresshd`
  initramfs hook re-enables it before userspace even starts, so a lockout cannot
  survive a reboot.
- Omarchy's `omarchy-fcitx5.service` restart-loops without fcitx5 and steals
  Hyprland's single input-method slot from squeekboard: mask it.
- squeekboard only auto-shows on text focus with
  `gsettings set org.gnome.desktop.a11y.applications screen-keyboard-enabled true`,
  and it must bind while a text client already holds focus: an input method that
  connects to an empty session never receives activation again. `fajita-osk-start`
  opens a throwaway terminal to prime that, which is why the OSK is a systemd user
  service rather than a Hyprland `exec`.
- Never resolve the Hyprland session with `ls -t $XDG_RUNTIME_DIR/hypr/`. With no
  RTC the clock starts at 1970, so stale session directories sort newer than the
  live one and scripts silently drive a dead compositor. Use `hyprctl instances`.

## Configuration

Everything adjustable lives in `config.env` (user, password, USB subnet, locale,
timezone, image size). Every script sources it, so edit that one file or export
the variables in your shell. Defaults: user `dan`, phone at `172.16.42.1`.

## Access

- `ssh $PHONE_USER@$PHONE_IP` over the USB NCM gadget (sudo NOPASSWD; install your
  key on first login, the password only ever crosses the USB link).
- Phone internet: on the host run `ssh -N -R 1080 $PHONE_USER@$PHONE_IP`; the phone's
  `/etc/profile.d/proxy.sh` points pacman/curl/git at `socks5h://127.0.0.1:1080`.
  The phone has no route of its own until you join Wi-Fi.
- On the phone: tap the top-left bar icon for the Omarchy menu, the keyboard icon
  at the top right toggles the on-screen keyboard.

## Phone adaptations beyond the build

`scripts/phone/apply-shell-patches.sh` patches Omarchy's own Quickshell interface
for touch. Re-run it after any `omarchy` package upgrade, since pacman replaces
those files:

- **Menu rows** get a `TapHandler`. Upstream handlers are pointer-only, and a
  finger tap on a layer surface never synthesizes a pointer event, so menus were
  unusable by touch.
- **Panel dismissal mask** subtracts the on-screen keyboard strip. The panel's
  full-screen click-catcher otherwise reads the first keypress as an outside
  click and closes the panel mid-typing.

Other phone-specific changes, applied by `phone-setup.sh`:

- Qt/GTK input-method variables point at `wayland`. Omarchy sets them to fcitx,
  which is masked here (its restart loop fights the on-screen keyboard), leaving
  Omarchy's own text fields with no keyboard at all.
- Suspend is masked. s2idle freezes userspace on this device with no wake path:
  the phone looks dead and ignores the power button.
- Arch's `man-db`, `plocate-updatedb` and `shadow` timers are masked. They
  saturate the SDM845 for minutes after boot and read as a hang.
- The screensaver's effects engine, `ttfx`, is x86_64-only upstream. A shim maps
  it to `tte` from `python-terminaltexteffects` with the frame rate clamped, and
  the screensaver ships disabled: the Python engine at 120fps wedges the phone.

## Rebuild from scratch

1. Docker Desktop up. `docker run -d --name fajita-build --privileged --platform linux/arm64 -v $PWD/work:/work ubuntu:24.04 sleep infinity`, apt install e2fsprogs cpio arch-install-scripts android-sdk-libsparse-utils build-essential git zstd systemd-container, build osm0sis/mkbootimg with `CFLAGS="-O2 -w"`.
2. Download `ArchLinuxARM-aarch64-latest.tar.gz` and the pmOS v25.12 apks
   (`linux-postmarketos-qcom-sdm845`, `firmware-oneplus-sdm845`, `device-oneplus-fajita`) into `work/`, extract apks under `work/pmos/x/`.
3. `docker exec fajita-build bash /work/scripts/build-rootfs.sh`
4. Phone: OEM unlocking on, USB debugging on, USB 2.0 cable. `scripts/flash.sh unlock`, then `scripts/flash.sh flash`.
5. Fetch the arch=any Omarchy packages from `https://pkgs.omarchy.org/x86_64` into `work/opkgs/`, start the reverse tunnel, run `scripts/phone-setup.sh`.

## Status

Working: boots unattended into the Omarchy session, bar, menu (touch), on-screen
keyboard, terminal, theme, GPU acceleration, audio, Wi-Fi, USB networking, ssh,
screenshots (`scripts/shot.sh`).

Not working: Bluetooth (firmware loads, HCI reset times out), lock screen,
cellular. Camera and sensors untouched.

Tested only on a OnePlus 6T (fajita) with Omarchy 4.0.2 and Hyprland 0.56.2.
The OnePlus 6 (enchilada) shares the SoC and should need only a DTB change.
