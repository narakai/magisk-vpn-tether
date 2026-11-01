# magisk-vpn-tether

Share a rooted Android phone's **VPN** with the devices connected to its **hotspot** (DNS included),
with one tap on the Magisk module's **Action** button.

[中文说明](README.zh-CN.md)

## Why this is needed

When you tether, Android sends the hotspot clients' traffic out of the *uplink* (Wi-Fi or mobile data),
not into the VPN, even though the phone itself is using the VPN. Two things cause it:

- a system rule `from all iif <hotspot> lookup <uplink table>` (priority 21000) picks the uplink's routing table;
- the firewall chain `tetherctrl_FORWARD` only allows `hotspot -> uplink`, and NAT only masquerades out of the uplink.

On top of that, the hotspot's DNS is served by the tether `dnsmasq`, which forwards clients' queries to the
**uplink router's DNS**. Even when the traffic is fixed, the domain names still leak.

## What it does

`Action` toggles these rules (all in memory):

1. `ip rule add pref 20500 iif <hotspot> lookup <VPN table>` (IPv4 and IPv6; must sort before 21000)
2. firewall: accept `hotspot -> VPN`, and the return traffic
3. `MASQUERADE` the hotspot subnet out of the VPN interface
4. `DNAT` the clients' port-53 traffic to the VPN's DNS

Since v1.1.0 a small background **watcher** keeps them applied: after you tapped Action once, it checks every few seconds and
re-applies the rules when Android drops them (hotspot toggled, VPN reconnected, tethering rebuilt), and removes them when the hotspot
is gone. Tap Action again to turn it off (then the watcher stops re-applying). With `AUTO=0` nothing runs in the background and the
rules are in memory only, as in v1.0.x.

## Requirements

- Rooted with **Magisk** (the Action button needs a Magisk version that supports module actions; v28+ shows it, I used 30.7).
- A VPN app that uses Android's VPN service and creates a `tun` interface (tested with NekoBox / sing-box).
- Kernel with netfilter NAT, `MASQUERADE`, policy routing and the `comment` match (common on stock-based kernels).

## Install

1. Download `vpn-tether-<version>.zip` from the [Releases](../../releases) page.
2. Magisk app -> Modules -> *Install from storage* -> pick the zip -> **reboot once** (the Action button appears after the reboot).

## Use

1. Turn on the VPN.
2. Turn on the hotspot.
3. Magisk -> Modules -> *VPN Tether* -> **Action**. The output tells you what was applied, or what is missing.
4. Connect the client. Tap **Action** again to turn it off.

Turn the hotspot on **after** the VPN. After that you do not have to tap Action again: the watcher re-applies the rules when you toggle
the hotspot or the VPN reconnects (within `INTERVAL` seconds, default 5; the first tap is still needed after a fresh install, because
sharing your VPN is something you turn on on purpose). The "on" flag is `/data/adb/vpn-tether.on` and survives a reboot; what the watcher
did is logged in `/data/adb/vpn-tether.log`. Tap Action while it is ON to turn sharing off for good.

**If the hotspot clients suddenly lose internet** while this is on (with `AUTO=0`, or before the watcher has caught up): Android sometimes rebuilds its own tethering firewall
chains while the hotspot is running (for example when it re-evaluates the upstream network). That drops the forward and
masquerade rules of this module, while the routing rule stays, so the client's packets are sent into the VPN and then dropped.
Tap **Action** once: since v1.0.1 the script detects this half-applied state (`status` prints `PARTIAL`) and re-applies instead of
switching off. If it cannot re-apply (for example the hotspot is gone) it removes the leftovers. With the watcher (default since v1.1.0) you do not
have to tap.

Without the Magisk UI: `su -c "sh /data/adb/modules/vpn_tether/vpn-tether.sh on|off|toggle|status"` (`watch` runs the watcher in the foreground).
To see what would be auto-detected (VPN interface and table, VPN DNS, hotspot interface and subnet): `su -c "sh /data/adb/modules/vpn_tether/vpn-tether.sh detect"`.

**After you restart the VPN, make the hotspot clients reconnect to the hotspot** (turn their Wi-Fi off and on, or airplane mode on/off).
If the VPN uses *fake-IP* DNS (the default in many sing-box / NekoBox setups: DNS answers come from `198.18.0.0/15` with a TTL of
about 10 minutes), the fake-IP table is reset when the VPN restarts, but the client keeps the old answers in its DNS cache, so its
connections go to addresses that no longer map to anything and pages do not open. Reconnecting (or waiting for the cache to expire)
fixes it; the rules themselves are fine. Seen on the test phone: after VPN off, Action off, VPN on, Action on, the iPhone could not
load pages until its Wi-Fi was reconnected.

## Configuration

Defaults are in `config.sh`. To change them put overrides in **`/data/adb/vpn-tether.conf`** (survives module updates):

```sh
HS="wlan1"        # hotspot interface(s), space separated. Empty = auto-detect from the tethering rule
TUN="tun0"        # VPN interface. Empty = auto-detect (tun*/wg*/ppp*/tap* with a default route)
VPN_DNS="auto"    # auto | off | a.b.c.d
AUTO=1            # 1 = background watcher keeps the rules applied, 0 = no background process
INTERVAL=5        # seconds between two watcher checks
```

`VPN_DNS=auto` assumes a sing-box-style tun address `x.x.x.1/30` and uses `x.x.x.2` as the DNS (that is where
sing-box's DNS hijack listens). For other VPN clients set an IPv4 that is reachable through the VPN, or `off`
(then the clients' DNS leaks through the uplink, and the script prints a warning).

## Verified, and not

Tested on **one device**: Xiaomi M2012K11AG (alioth), MIUI 14 / Android 13, kernel 4.19, Magisk 30.7,
NekoBox (sing-box) VPN, uplink Wi-Fi, an iPhone as the hotspot client.

- Hotspot traffic left through the VPN interface (`conntrack` showed the NATed source on `tun0`).
- Before the DNS rule, 80 of 80 DNS queries from the client went to the uplink router. With it, all 47 queries seen in a
  24-second sample were redirected to the VPN's DNS and none went to the router; dnsleaktest on the client showed the VPN's exit
  (checked with an earlier revision of the same rules).
- `on`, repeated `on`, `off`, `toggle`, `status`, the missing-VPN / missing-hotspot / bad-config error paths and `VPN_DNS=off`
  were exercised on the phone, in Magisk's busybox standalone shell, with the final script.
- The half-applied state was reproduced by deleting this module's rules from the tether chains: `status` reports `PARTIAL`,
  `toggle` re-applies, and with no usable hotspot interface it cleans up. That loss also happened once for real on the test phone;
  I did not capture the exact moment, I only saw the rules gone shortly after a tethering upstream re-evaluation in the system log.

The watcher (v1.1.0) was tested on the same phone: deleting the module's forward and masquerade rules made it re-apply within 2 seconds
(`INTERVAL=2` in that test), `off` was not undone by it, and a second `on` did not start a second watcher. Not tested: a real hotspot toggle
while it runs, and a reboot (the `service.sh` start).

Not verified: other devices / ROMs / Android versions, other VPN clients, USB or Bluetooth tethering, IPv6 clients
(the VPN table normally has no IPv6 default, so IPv6 should fall back to IPv4, but I did not test it), the interplay
with Android's BPF tethering offload on other kernels.
Auto-detection of the hotspot interface assumes the system's tethering rule uses priority 21000, which is AOSP's value.

## Safety

- Needs root and edits firewall and routing rules. Read `module/vpn-tether.sh` first (about 250 lines).
- With the watcher, once you turned sharing on, **every hotspot you open later also gets your VPN** until you tap Action to turn it off.
  Set `AUTO=0` if you do not want that.
- Anyone connected to your hotspot gets to use your VPN. Use a hotspot password.
- Some VPN providers do not allow sharing a connection with other devices: check yours.
- No warranty.

## Remove

Disable or remove the module in Magisk. To clear the rules at once: Action again (this also stops the watcher from re-applying).

## Build from source

```sh
./build.sh      # -> dist/vpn-tether-<version>.zip
```

## License

MIT, see [LICENSE](LICENSE).
