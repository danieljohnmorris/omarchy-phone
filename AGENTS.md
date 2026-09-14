# AGENTS.md

Omarchy ports to Android phones (currently OnePlus 6T / fajita: Arch Linux ARM
on the postmarketOS SDM845 kernel, Hyprland, Omarchy 4).

Read [CLAUDE.md](CLAUDE.md) before doing anything: it maps the repo, lists the
postmarketOS components and why each is needed, and holds the gotchas (no RTC,
suspend never resumes, IMS bearer needs hand-configuration, omarchy-update
clobbers local files). The device journal in
[omarchy-android-oneplus6t/README.md](omarchy-android-oneplus6t/README.md) is
the detailed record for build and modem behaviour.

Rules that matter most: probe the live phone before theorising, deploy and
re-run `check-sync.sh` in the same change, and never overwrite `main`.
