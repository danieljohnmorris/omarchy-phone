#!/bin/bash
# Provision the SIM's primary GW provisioning session on Qualcomm QMI modems.
# Port of postmarketOS msm-modem-uim-selection to systemd.
#
# Why: this firmware (OnePlus 6T, MPSS.AT.4.0) never provisions a primary GW
# UIM session itself (Android's RIL uses per-app sessions). Without it,
# ModemManager's unlock check fails with "GW primary session index unknown",
# the modem init aborts and lands in a bogus failed/sim-missing state. The
# session must be (re-)established after every modem reboot/power-cycle, so
# this runs at boot and ModemManager is ordered after it.
set -euo pipefail
QMICLI=/usr/bin/qmicli

# Wait for the modem PD to publish DMS on qrtr (fresh boot: a few seconds)
for i in $(seq 1 30); do
    if $QMICLI -pd qrtr://0 --dms-get-operating-mode >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

STATUS=$($QMICLI -pd qrtr://0 --uim-get-card-status)

# Find the first slot with a present card and a usim application; grab its AID.
# Card status shape:
#   Slot [2]:
#   \tCard state: 'present'
#   \t\tApplication type: 'usim (2)'
#   \t\tApplication ID:  A0:00:...
AID=$(printf '%s' "$STATUS" | awk '
    /^Slot \[/   { slot = $0; present = 0; next }
    /Card state/ { present = ($0 ~ /present/) ? 1 : 0; next }
    present && /Application ID:/ { sub(/.*Application ID:[ ]*/, ""); print; exit }
')
[ -n "$AID" ] || { echo "no usim AID found in card status" >&2; exit 1; }
SLOT=$(printf '%s' "$STATUS" | awk -v want="$AID" '
    /^Slot \[/   { gsub(/[^0-9]/, "", $0); slot = $0; next }
    present && /Application ID:/ { sub(/.*Application ID:[ ]*/, ""); if ($0 == want) { print slot; exit } next }
    /Card state/ { present = ($0 ~ /present/) ? 1 : 0 }
')
[ -n "$SLOT" ] || SLOT=1

echo "provisioning slot $SLOT AID $AID"
exec $QMICLI -pd qrtr://0 --uim-change-provisioning-session="slot=$SLOT,activate=yes,session-type=primary-gw-provisioning,aid=$AID"
