#!/system/bin/sh
# Magisk late_start service: start the watcher (it only acts after you turned sharing on with Action,
# and does nothing at all when AUTO=0 in config).
MODDIR=${0%/*}
nohup sh "$MODDIR/vpn-tether.sh" watch >/dev/null 2>&1 </dev/null &
