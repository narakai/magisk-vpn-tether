# Changelog

## v1.0.1
- `status` now reports `OFF`, `ON` or `PARTIAL`. Android can rebuild its tethering firewall chains while the hotspot runs, which
  drops the module's forward and masquerade rules but not its routing rule or DNS redirect; clients then lose internet.
- `toggle` (the Action button) re-applies in the `PARTIAL` state instead of switching off, and cleans up if it cannot re-apply.

## v1.0.0
- First release: ip rule + firewall forward + MASQUERADE + DNS redirect for hotspot clients through the VPN, Magisk Action toggle,
  auto-detection of the VPN and hotspot interfaces, `/data/adb/vpn-tether.conf` overrides.
