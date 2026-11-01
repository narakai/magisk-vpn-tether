# Changelog

## v1.1.0
- Background watcher (`service.sh`, `vpn-tether.sh watch`): after you turned sharing on with Action, it re-applies the rules within a few
  seconds when Android drops them (tethering rebuilt, hotspot toggled, VPN reconnected with another table), and removes them when the
  hotspot is gone. No more tapping Action after each of those. `off` (tap Action while ON) stops it from re-applying.
- New config: `AUTO` (1 = watcher, 0 = nothing runs in the background, as in v1.0.x) and `INTERVAL` (seconds between checks, default 5).
- Re-applications are logged to `/data/adb/vpn-tether.log`. The "sharing is on" flag is `/data/adb/vpn-tether.on` and survives reboots.

## v1.0.1
- `status` now reports `OFF`, `ON` or `PARTIAL`. Android can rebuild its tethering firewall chains while the hotspot runs, which
  drops the module's forward and masquerade rules but not its routing rule or DNS redirect; clients then lose internet.
- `toggle` (the Action button) re-applies in the `PARTIAL` state instead of switching off, and cleans up if it cannot re-apply.

## v1.0.0
- First release: ip rule + firewall forward + MASQUERADE + DNS redirect for hotspot clients through the VPN, Magisk Action toggle,
  auto-detection of the VPN and hotspot interfaces, `/data/adb/vpn-tether.conf` overrides.
