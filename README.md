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

Nothing runs at boot, there is no service. The rules disappear when the hotspot is toggled or the phone reboots.
Tap Action again to turn it off.

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

Turn the hotspot on **after** the VPN, and tap Action again after you toggle the hotspot or the VPN reconnects.

Without the Magisk UI: `su -c "sh /data/adb/modules/vpn_tether/vpn-tether.sh on|off|toggle|status"`.
To see what would be auto-detected (VPN interface and table, VPN DNS, hotspot interface and subnet): `su -c "sh /data/adb/modules/vpn_tether/vpn-tether.sh detect"`.

## Configuration

Defaults are in `config.sh`. To change them put overrides in **`/data/adb/vpn-tether.conf`** (survives module updates):

```sh
HS="wlan1"        # hotspot interface(s), space separated. Empty = auto-detect from the tethering rule
TUN="tun0"        # VPN interface. Empty = auto-detect (tun*/wg*/ppp*/tap* with a default route)
VPN_DNS="auto"    # auto | off | a.b.c.d
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

Not verified: other devices / ROMs / Android versions, other VPN clients, USB or Bluetooth tethering, IPv6 clients
(the VPN table normally has no IPv6 default, so IPv6 should fall back to IPv4, but I did not test it), the interplay
with Android's BPF tethering offload on other kernels.
Auto-detection of the hotspot interface assumes the system's tethering rule uses priority 21000, which is AOSP's value.

## Safety

- Needs root and edits firewall and routing rules. Read `module/vpn-tether.sh` first (about 149 lines).
- Anyone connected to your hotspot gets to use your VPN. Use a hotspot password.
- Some VPN providers do not allow sharing a connection with other devices: check yours.
- No warranty.

## Remove

Disable or remove the module in Magisk. To clear the rules at once: Action again, or turn the hotspot off.

## Build from source

```sh
./build.sh      # -> dist/vpn-tether-<version>.zip
```

## License

MIT, see [LICENSE](LICENSE).
