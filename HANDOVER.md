# HANDOVER — build & deploy omarchy-phone

For an agent on the Omarchy computer that must build
`danieljohnmorris/omarchy-phone` (branch `phone-cellular`) from scratch and
flash + deploy it to a OnePlus 6T ("fajita"). Written 2026-09-15 from a live
session; every command below was run on the real device unless marked
UNTESTED.

Paths are relative to the repo root (the directory containing this file,
`AGENTS.md`, `README.md`, and `omarchy-android-oneplus6t/`). Secrets and
connection details come from `omarchy-android-oneplus6t/config.env` — never
commit or paste them. This doc deliberately contains no usernames, IPs, or
phone numbers.

## Suggested skills

- `diagnose` — every bug on this device so far was found by
  reproduce → instrument → falsify, not by guessing. Use it for any
  regression.
- `where-was-i` — this repo's state lives partly on the phone, partly in the
  tree; reconstruct before acting on a stale session.
- `unlazy` — the verify-everything discipline this codebase expects
  (on-device proof for every claim).
- `caveman` — if the operator asks for terse output.

## 0. Prerequisites (Omarchy computer)

- Docker Desktop running (Apple Silicon: arm64 containers run natively).
- Android platform-tools: `adb` + `fastboot` on PATH (Linux `android-tools`
  package, macOS `~/Library/Android/sdk/platform-tools`) — `flash.sh` falls
  back to the macOS path and errors if neither exists.
- A **USB 2.0 cable** — fastboot on this device is unreliable over USB 3.
- `git` on branch `phone-cellular`.

## 1. Build the rootfs image

### 1a. Stage artifacts into `work/` (gitignored)

```sh
cd omarchy-android-oneplus6t
mkdir -p work/pmos/x work/out

# Arch Linux ARM base
curl -LO https://dl.armmirror.com/archlinuxarm/os/ArchLinuxARM-aarch64-latest.tar.gz   # or os.archlinuxarm.org

# pmOS packages: kernel, firmware, device package (apk = gzipped tarball).
# Fetch each .apk, then extract each into its own dir under work/pmos/x/:
for f in linux-postmarketos-qcom-sdm845-*.apk firmware-oneplus-sdm845-*.apk device-oneplus-fajita-*.apk; do
  d="work/pmos/x/${f%.apk}"; mkdir -p "$d"; tar -xzf "$f" -C "$d"
done
# build-rootfs.sh globs work/pmos/x/linux-postmarketos-qcom-sdm845-*/ and
# work/pmos/x/firmware-oneplus-sdm845-<ver>*/ — keep the layout exact.

# arch=any Omarchy packages (the x86_64 repo's repackagable subset)
# from https://pkgs.omarchy.org/x86_64 into work/opkgs/
```

### 1b. Build container — mount scripts AND config separately

A `/work`-only mount is NOT enough: `build-rootfs.sh` reads `/work/scripts/…`
and `/work/config.env`. Mount all three (or a staged tree):

```sh
docker run -d --name fajita-build --privileged --platform linux/arm64 \
  -v "$PWD/work:/work" \
  -v "$PWD/scripts:/work/scripts" \
  -v "$PWD/config.env:/work/config.env" \
  ubuntu:24.04 sleep infinity

docker exec fajita-build bash -c \
  'apt-get update && apt-get install -y e2fsprogs cpio arch-install-scripts \
   android-sdk-libsparse-utils build-essential git zstd systemd-container \
   && git clone --depth 1 https://github.com/osm0sis/mkbootimg /tmp/mkbootimg \
   && make -C /tmp/mkbootimg CFLAGS="-O2 -w"'
```

`ROOTFS_SIZE` is now read *after* `config.env` is sourced
(`build-rootfs.sh:19`), so a fresh container no longer dies under `set -u`.
Override it with `docker exec -e ROOTFS_SIZE=16G …` if wanted.

### 1c. Build

```sh
docker exec fajita-build bash /work/scripts/build-rootfs.sh
ls -la work/out/   # expect boot.img + rootfs.img (or rootfs.simg)
```

Builds Hyprland, patched ModemManager, ttfx, 81voltd from source inside the
container. Kernel and firmware come from the pmOS apks — never build them.

## 2. Flash the phone (DESTRUCTIVE — wipes userdata)

```sh
scripts/flash.sh unlock     # confirm bootloader-unlock ON THE PHONE (VolUp + Power); wipes data
scripts/flash.sh flash      # erases dtbo, flashes boot + userdata, reboots
# scripts/flash.sh boot-test  boots work/out/boot.img WITHOUT flashing — use for kernel experiments
```

After flashing, ~30 s later a new USB ethernet interface appears (gadget
NIC; name varies — see §4).

## 3. First deploy after flash

1. On the computer: reverse SOCKS tunnel so the phone gets internet
   (`config.env: PROXY_PORT`, default 1080). Without it, `pacman`, `git`,
   and `curl` on the phone all fail.

2. `scripts/phone-setup.sh` — installs everything: fajita-* helpers, QML
   apps, shell patches, polkit rules, q6voiced, 81voltd, backlight floor,
   ALSA-state masks. Needs the tunnel up.
3. Gate: `scripts/check-sync.sh` must print `repo matches the phone`
   (`--pull` to copy phone → repo when the phone has drifted).

## 4. SSH tips & tricks (this device)

- **Transport is IPv6 link-local over the USB gadget NIC.** There is no
  `fajita` hostname. Target: `$PHONE_USER@fe80::…%<iface>` (build it from
  `config.env`).
- **Interface numbers change.** After every re-plug, macOS may renumber the
  gadget NIC (`en16` → something else). Poll *all* interfaces, not one name:

  ```sh
  for i in $(ifconfig -l | tr ' ' '\n' | grep '^en'); do
    ssh -o ConnectTimeout=3 "$PHONE_USER@fe80::…%$i" true 2>/dev/null \
      && echo "phone on $i" && break
  done
  ```

  Fastest reliable check: `ssh -o ConnectTimeout=5 "$P" uptime`.
- **scp is flaky on this link** (drops mid-transfer, connection closed).
  Pipe over ssh instead: `ssh "$P" 'cat > /tmp/f' < localfile` and
  `ssh "$P" 'cat /tmp/f' > localfile`.
- **Non-login shells have no `~/.local/bin`** in PATH — every fajita-*
  helper needs `export PATH="$HOME/.local/bin:$PATH"` prefix, or full path.

- **Quoting:** remote one-liners with `$()`/loops go in **single quotes**;
  nested heredocs over ssh will bite — write a script locally and
  `ssh "$P" bash -s < script.sh` instead.
- No RTC: the phone boots at 1970 until NTP lands. Never trust its clock for
  "is this fresh" reasoning; compare md5s, not mtimes.

## 5. Screenshots

```sh
scripts/shot.sh out.png    # grim on the phone, pulled over ssh
```

Manual equivalent (when scp drops): `ssh "$P" 'grim /tmp/s.png && cat /tmp/s.png' > out.png`.
scp/redirect do NOT preserve the phone's mtime — a stale-looking local file
can be current; verify freshness by the on-screen clock or a fresh md5.

## 6. Reboot & rescue

- Normal: `ssh "$P" 'sudo reboot'` (comes back in ~1 min).
- Bootloader: from adb `adb reboot bootloader`, or hold **Power+VolUp+VolDown**
  (on-device prompt on `flash.sh unlock`).
- Recovery/fastboot rescue: **Power+VolUp+VolDown held ~20–25 s**.
- Force power-off from Qualcomm crashdump/EDL-looking states: hold **Power
  ~10–12 s** until vibrate, then Power.
- **No USB enumeration ≠ dead.** Check `ifconfig -l` for a renumbered NIC
  before assuming crashdump; also check `fastboot devices`. Crashdump mode
  typically does not enumerate at all.
- After any rescue boot, expect the RTC reset and a screen-blank phase —
  `fajita-backlight-floor.service` clamps restored brightness up to 20% at
  boot (reads `/sys/class/backlight/ae94000.dsi.0`).

## 7. Manual builds of committed binaries

- **ttfx** (screensaver engine): `scripts/build-ttfx.sh` — Docker arm64,
  Debian bookworm base (older glibc → runs on phone's newer Arch glibc),
  rustup toolchain (apt's rustc 1.63 is below ttfx's MSRV; Alpine/musl cannot
  build its proc-macro crates). Output committed at
  `scripts/phone/ttfx-aarch64`, installed by `phone-setup.sh` to
  `/usr/local/bin/ttfx`. **Verify with `ttfx --version` → 0.3.2, never by
  sha256** — rebuilds differ (BuildID). NEVER substitute Python `tte`: at
  Omarchy's 120fps it saturates the SDM845 and the screensaver respawn loop
  wedged the session at load 229 once.
- **q6voiced** (voice-call daemon): `scripts/build-q6voiced.sh` — Docker
  arm64, builds the **tracked fork** `scripts/phone/q6voiced.c` (per-leg open
  with retry; upstream never retries a failed pcm_open and one flaky open
  silenced calls), links tinyalsa statically-ish, only libc/libdbus dynamic.
  Result is copied to `scripts/phone/q6voiced` (tracked) and deployed to
  `/usr/local/bin` by `phone-setup.sh`.

## 8. Call-audio debugging (the current open problem)

Status as of handover: **uplink confirmed** (far end hears the phone).
**Downlink still unproven** — a clean-boot retest after the ALSA-state masks
was interrupted. Verify state first:

```sh
# Voice FE legs — the kernel starts the voice path ONLY when BOTH are open
ssh "$P" 'grep -H . /proc/asound/card0/pcm6{p,c}/sub0/status 2>/dev/null'
# Both must print "state: PREPARED". If pcm6c is missing/SETUP, the session
# is half-open and there is no call audio in either direction.

# One-shot dump: verb, csets, PCM state
ssh "$P" 'export PATH=$HOME/.local/bin:$PATH; fajita-call-audio-diag'

# Route + mic gate state files (watcher re-applies saved route per profile flip)
ssh "$P" 'cat ~/.local/state/fajita/call-route ~/.local/state/fajita/call-mic 2>/dev/null'

# Daemon + kernel evidence
ssh "$P" 'journalctl -u q6voiced -n 50 --no-pager; sudo dmesg | tail -50'
# AFE errors look like: qcom-q6afe ... AFE enable for port 0x… failed -22

# ADSP session debug (dynamic debug resets on every boot — re-arm):
ssh "$P" 'for m in q6voice q6mvm q6cvp q6afe; do echo "module $m +p" | sudo tee /sys/kernel/debug/dynamic_debug/control; done'
# then dial and read: sudo dmesg | grep -E "q6mvm|q6cvp|MVM|CVP"
```

- Mute is a **digital gain** (`DEC7 Volume` 0/84) — never toggle
  `VoiceMMode1 Capture Mixer *` mid-call: it closes TX port 7 permanently
  (dmesg: `Port Closed TX port 7`), killing the uplink for the rest of the
  call. Route switches too.
- The calls app graph label says `voice FE prepared` — that is FE state only,
  it CANNOT see downlink media. Do not treat it as audio evidence.
- Speaker route must be applied **after** the FE opens (watcher re-applies
  the saved route detached, ~3 s wait). QUAT_MI2S before the FE opens kills
  the downlink of that call.
- pmOS deltas already applied and persisted in `phone-setup.sh`:
  `alsa-restore.service` + `alsa-state.service` masked to /dev/null,
  `/var/lib/alsa/asound.state` removed (pmOS preset: restored mixer state
  breaks audio; pmaports#3747/#3320).
- If the clean-boot downlink test fails, remaining unexplored deltas vs pmOS:
  `firmware-oneplus-sdm845` version (pmOS ≥9 vs the pinned apk in work/), and
  modem/QMI RX path. Kernel is NOT the delta: 6.16.7 → pmOS 7.1-rc1 q6voice
  core diff is cosmetic (no functional change found in q6voice/mvm/cvs files;
  q6afe/q6routing/codec not diffed).

## 9. Conventions

- Never overwrite `main`. Work on `phone-cellular`, fast-forward at session
  end. Commit subjects name the subsystem (Calls, Shell, Toasts, phone-setup…).
- Before declaring done: `scripts/check-sync.sh` → `repo matches the phone`,
  and every deployed file's md5 must match the committed tree.
- Evidence first: probe the phone (ssh, mmcli, dmesg, journalctl) before
  theorising; falsify hypotheses by forcing the predicted failure, not by
  reading code. Several plausible mechanisms here were falsified by exactly
  that test (see the device README's journal).
- The device README (`omarchy-android-oneplus6t/README.md`) is the long-form
  journal of every dead end — search it before repeating an experiment.
