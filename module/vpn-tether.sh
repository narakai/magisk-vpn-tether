#!/system/bin/sh
# vpn-tether.sh - share the phone's VPN with its hotspot clients.
#
# Usage (as root):  sh vpn-tether.sh on | off | toggle | status | detect
#
# Android normally sends hotspot traffic out of the uplink (Wi-Fi / mobile data), never into the
# VPN. This adds, in memory only (gone after a hotspot toggle or reboot):
#   1. an ip rule: packets arriving from the hotspot interface use the VPN's routing table
#   2. iptables FORWARD accepts hotspot <-> VPN, and MASQUERADE out of the VPN interface
#   3. a DNAT of the clients' port-53 traffic to the VPN's DNS (otherwise the tether dnsmasq
#      forwards their DNS to the uplink router: a DNS leak)
# Every iptables rule carries the comment "vpn-tether", which is how `off` finds them again.

# Real tools by absolute path: Magisk runs module scripts in busybox "standalone" mode, where a bare
# `ip` is busybox's limited applet (no `iif`) and `ip rule add` fails.
IP=/system/bin/ip
IPT=/system/bin/iptables
TAG=vpn-tether
PREF=20500          # our ip rule priority; must be lower than the tethering rule's 21000
TETHER_PREF=21000

case $0 in */*) MODDIR=${0%/*} ;; *) MODDIR=. ;; esac
HS=""; TUN=""; VPN_DNS=auto
[ -f "$MODDIR/config.sh" ] && . "$MODDIR/config.sh"
[ -f /data/adb/vpn-tether.conf ] && . /data/adb/vpn-tether.conf

fail() { echo "Not applied: $*"; exit 1; }
is_on() { $IP rule | grep -q "^$PREF:"; }

count_rules() {   # count_rules <table> <chain>: how many of our tagged rules are in a chain
    $IPT -t "$1" -S "$2" 2>/dev/null | grep -c -e "--comment $TAG"
}

# OFF     = none of our rules exist
# ON      = the routing rule, and per hotspot interface 2 forward rules + 1 masquerade, all exist
# PARTIAL = anything else. Android rebuilds its own tetherctrl_* chains when the tethering upstream is
#           re-evaluated, which drops our rules inside them while the routing rule and the DNAT survive.
state() {
    ipn=$($IP rule | grep -c "^$PREF:")
    fwd=$(count_rules filter tetherctrl_FORWARD)
    masq=$(count_rules nat tetherctrl_nat_POSTROUTING)
    dnat=$(count_rules nat PREROUTING)
    if [ "$ipn" -eq 0 ] && [ "$fwd" -eq 0 ] && [ "$masq" -eq 0 ] && [ "$dnat" -eq 0 ]; then
        echo OFF
    elif [ "$ipn" -ge 1 ] && [ "$fwd" -ge $((2 * ipn)) ] && [ "$masq" -ge "$ipn" ]; then
        echo ON
    else
        echo PARTIAL
    fi
}

detect_tun() {
    $IP route show table all 2>/dev/null | awk '$1=="default" && $2=="dev" && $4=="table" && $3 ~ /^(tun|wg|ppp|tap)/ {print $3; exit}'
}
tun_table() {
    $IP route show table all 2>/dev/null | awk -v t="$1" '$1=="default" && $2=="dev" && $3==t && $4=="table" {print $5; exit}'
}
detect_hs() {
    $IP rule 2>/dev/null | awk -v p="$TETHER_PREF:" '$1==p && $4=="iif" {print $5}' | sort -u | tr '\n' ' '
}
hs_net() {
    $IP route show dev "$1" proto kernel 2>/dev/null | awk '{print $1; exit}'
}
# /30 peer address of an interface (172.19.0.1/30 -> 172.19.0.2)
derive_dns() {
    $IP -4 addr show dev "$1" 2>/dev/null | awk '/inet / {
        split($2, a, "/"); split(a[1], o, ".")
        if (a[2] == 30) {
            m = o[4] % 4
            if (m == 1) print o[1] "." o[2] "." o[3] "." (o[4] + 1)
            else if (m == 2) print o[1] "." o[2] "." o[3] "." (o[4] - 1)
        }
        exit }'
}

ipt() {   # ipt <iptables args...>: run, and report errors
    out=$($IPT "$@" 2>&1) || { echo "iptables $* failed: $out"; return 1; }
}

remove_rules() {
    while $IP rule del pref $PREF 2>/dev/null; do :; done
    while $IP -6 rule del pref $PREF 2>/dev/null; do :; done
    for spec in "filter tetherctrl_FORWARD" "nat tetherctrl_nat_POSTROUTING" "nat PREROUTING"; do
        table=${spec%% *}; chain=${spec##* }
        $IPT -t $table -S $chain 2>/dev/null | grep -e "--comment $TAG" | sed 's/^-A /-D /' |
            while read -r line; do $IPT -t $table $line 2>/dev/null; done
    done
}

do_on() {
    [ -n "$TUN" ] || TUN=$(detect_tun)
    [ -n "$TUN" ] || fail "no VPN interface found (looked for tun*/wg*/ppp*/tap* with a default route). Turn on the VPN first, or set TUN in /data/adb/vpn-tether.conf."
    $IP link show "$TUN" >/dev/null 2>&1 || fail "VPN interface $TUN does not exist. Turn on the VPN first."
    TBL=$(tun_table "$TUN")
    [ -n "$TBL" ] || fail "$TUN has no default-route table (is the VPN connected?)."

    HSL="$HS"
    [ -n "$HSL" ] || HSL=$(detect_hs)
    [ -n "$HSL" ] || fail "no hotspot interface found. Turn on the hotspot first, or set HS in /data/adb/vpn-tether.conf."
    for h in $HSL; do
        $IP link show "$h" >/dev/null 2>&1 || fail "hotspot interface $h does not exist. Turn on the hotspot first."
    done

    DNS=""
    case "$VPN_DNS" in
        off) ;;
        auto) DNS=$(derive_dns "$TUN") ;;
        *) echo "$VPN_DNS" | grep -Eq '^[0-9]+(\.[0-9]+){3}$' && DNS="$VPN_DNS" || fail "VPN_DNS='$VPN_DNS' is not auto, off or an IPv4 address." ;;
    esac

    remove_rules   # idempotent: start clean
    done_any=""
    for h in $HSL; do
        NET=$(hs_net "$h")
        [ -n "$NET" ] || { echo "skipped $h: no IPv4 subnet"; continue; }
        ERR=$($IP rule add pref $PREF iif "$h" lookup "$TBL" 2>&1) || { remove_rules; fail "ip rule add failed: $ERR"; }
        $IP -6 rule add pref $PREF iif "$h" lookup "$TBL" 2>/dev/null
        ipt -I tetherctrl_FORWARD 1 -i "$h" -o "$TUN" -m comment --comment $TAG -j ACCEPT || { remove_rules; fail "tethering firewall chain missing (is the hotspot really on?)"; }
        ipt -I tetherctrl_FORWARD 1 -i "$TUN" -o "$h" -m state --state RELATED,ESTABLISHED -m comment --comment $TAG -j ACCEPT
        ipt -t nat -I tetherctrl_nat_POSTROUTING 1 -s "$NET" -o "$TUN" -m comment --comment $TAG -j MASQUERADE
        if [ -n "$DNS" ]; then
            ipt -t nat -I PREROUTING 1 -i "$h" -p udp --dport 53 -m comment --comment $TAG -j DNAT --to-destination "$DNS:53"
            ipt -t nat -I PREROUTING 1 -i "$h" -p tcp --dport 53 -m comment --comment $TAG -j DNAT --to-destination "$DNS:53"
        fi
        echo "ON: $h ($NET) -> $TUN (table $TBL)"
        done_any=1
    done
    [ -n "$done_any" ] || fail "no hotspot interface had an IPv4 subnet."
    if [ -n "$DNS" ]; then
        echo "DNS of hotspot clients -> $DNS (through the VPN)"
    else
        echo "WARNING: DNS is not redirected (VPN_DNS=$VPN_DNS, none derived): hotspot clients' DNS goes through the uplink and can leak."
    fi
    is_on || fail "the routing rule is not present after adding it."
}

do_off() {
    remove_rules
    echo "OFF: hotspot clients are no longer routed through the VPN."
}

do_status() {
    st=$(state)
    echo "$st"
    [ "$st" = OFF ] && return 0
    $IP rule | grep "^$PREF:"
    echo "forward rules: $(count_rules filter tetherctrl_FORWARD), masquerade: $(count_rules nat tetherctrl_nat_POSTROUTING), dns redirect: $(count_rules nat PREROUTING)"
    [ "$st" = PARTIAL ] && echo "PARTIAL: the system rebuilt its tethering rules and dropped some of ours. Tap Action (or run toggle / on) to re-apply."
    return 0
}

# toggle: ON -> off; OFF -> on; PARTIAL -> re-apply (and if that is impossible, clean up what is left)
do_toggle() {
    case $(state) in
        ON) do_off ;;
        PARTIAL)
            echo "Some rules were lost (the system rebuilt its tethering rules). Re-applying."
            ( do_on )
            rc=$?
            if [ $rc -ne 0 ]; then
                remove_rules
                echo "Leftover rules removed: state is OFF."
                exit $rc
            fi
            ;;
        *) do_on ;;
    esac
}

do_detect() {
    t=${TUN:-$(detect_tun)}
    echo "VPN interface   : ${t:-<none found>}"
    if [ -n "$t" ]; then
        echo "VPN table       : $(tun_table "$t")"
        echo "VPN DNS (auto)  : $(derive_dns "$t")"
    fi
    h=${HS:-$(detect_hs)}
    echo "Hotspot iface(s): ${h:-<none found>}"
    for x in $h; do echo "  $x subnet: $(hs_net "$x")"; done
}

case "${1:-toggle}" in
    on) do_on ;;
    off) do_off ;;
    toggle) do_toggle ;;
    status) do_status ;;
    detect) do_detect ;;
    *) echo "usage: sh vpn-tether.sh on|off|toggle|status|detect"; exit 2 ;;
esac
