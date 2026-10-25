#!/system/bin/sh
# Magisk "Action" button: toggle sharing the VPN with the hotspot clients.
# Turn on the VPN, turn on the hotspot, then tap Action. Tap again to turn it off.
MODDIR=${0%/*}
sh "$MODDIR/vpn-tether.sh" toggle
exit $?
