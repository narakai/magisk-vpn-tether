# magisk-vpn-tether

在已 root 的安卓手机上，点一下 Magisk 模块的 **Action** 按钮，让连接手机**热点**的设备也走手机的 **VPN**（包括 DNS）。

[English](README.md)

## 为什么需要

开热点后，安卓默认把热点设备的流量从**上行网络**（Wi-Fi 或移动数据）发出去，不进 VPN，即使手机本身在用 VPN：

- 系统有一条按接口选路由表的规则 `from all iif <热点> lookup <上行表>`（优先级 21000）；
- 防火墙转发链 `tetherctrl_FORWARD` 只放行 `热点 -> 上行`，NAT 也只对上行做。

另外，热点的 DNS 由系统的 `dnsmasq` 提供，它会把设备的域名查询转给**上行路由器的 DNS**，所以就算流量走了 VPN，域名查询仍然泄漏。

## 做了什么

Action 开关下面这些规则（都只在内存里）：

1. `ip rule add pref 20500 iif <热点> lookup <VPN 路由表>`（IPv4 和 IPv6，优先级必须小于 21000）
2. 防火墙放行 `热点 -> VPN` 及回程流量
3. 对热点网段从 VPN 接口出去做 MASQUERADE
4. 把热点设备发往 53 端口的流量 DNAT 到 VPN 的 DNS

开机不运行任何东西，没有后台服务。关热点或重启后规则自动消失，再点一次 Action 就是关闭。

## 要求

- 已用 **Magisk** root（Action 按钮需要支持模块 Action 的 Magisk 版本，v28 以上有；我用的是 30.7）。
- VPN 应用使用安卓的 VPN 服务并生成 `tun` 接口（用 NekoBox / sing-box 测试过）。
- 内核支持 netfilter NAT、`MASQUERADE`、策略路由和 `comment` 匹配。

## 安装

1. 在 [Releases](../../releases) 下载 `vpn-tether-<版本>.zip`。
2. Magisk → 模块 → 从本地安装 → 选这个 zip → **重启一次**（重启后才会出现 Action 按钮）。

## 使用

1. 开 VPN。
2. 开热点。
3. Magisk → 模块 → *VPN Tether* → **Action**。输出会告诉你应用了什么，或缺什么。
4. 连接设备。再点一次 **Action** 即关闭。

请**先开 VPN，再开热点**。切换热点或 VPN 重连之后，要再点一次 Action。

**如果开着的时候，热点设备突然没网了**：安卓有时会在热点运行中重建自己的热点防火墙链（比如重新评估上游网络时），这会把本模块的转发放行和 MASQUERADE 规则一起删掉，而路由规则还在，于是设备的包被送进 VPN 又被丢掉。点一次 **Action** 就行：v1.0.1 起脚本能识别这种只剩一半的状态（`status` 显示 `PARTIAL`），会重新应用而不是关闭；如果没法重新应用（比如热点已经没了），会把残留规则清掉。故意没有做后台监控，所以需要你点一下。

不用 Magisk 界面：`su -c "sh /data/adb/modules/vpn_tether/vpn-tether.sh on|off|toggle|status"`。
想看自动识别到了什么（VPN 接口和路由表、VPN 的 DNS、热点接口和网段）：`su -c "sh /data/adb/modules/vpn_tether/vpn-tether.sh detect"`。

## 配置

默认值在 `config.sh`。要改请写到 **`/data/adb/vpn-tether.conf`**（模块更新不会丢）：

```sh
HS="wlan1"        # 热点接口，多个用空格分隔。留空 = 从系统的热点规则自动识别
TUN="tun0"        # VPN 接口。留空 = 自动识别（有默认路由的 tun*/wg*/ppp*/tap*）
VPN_DNS="auto"    # auto | off | a.b.c.d
```

`VPN_DNS=auto` 假定 tun 地址是 sing-box 风格的 `x.x.x.1/30`，并用 `x.x.x.2` 作为 DNS（sing-box 的 DNS 劫持就监听在那里）。别的 VPN 客户端请填一个通过 VPN 能访问的 IPv4，或填 `off`（此时设备的 DNS 会经上行泄漏，脚本会提示警告）。

## 验证了什么，没验证什么

只在**一台设备**上测过：Xiaomi M2012K11AG (alioth)，MIUI 14 / Android 13，内核 4.19，Magisk 30.7，NekoBox (sing-box) VPN，上行 Wi-Fi，用 iPhone 当热点客户端。

- 热点流量从 VPN 接口出去（`conntrack` 里能看到 NAT 后的源地址在 `tun0`）。
- 加 DNS 规则前，客户端 80 条 DNS 查询全部发给了上行路由器。加规则后，24 秒采样里看到的 47 条全部被重定向到 VPN 的 DNS，没有一条发给路由器；客户端上的 dnsleaktest 显示的是 VPN 出口（用的是同一套规则的早期版本）。
- 用最终的脚本，在 Magisk 的 busybox 独占 shell 里，实测了 `on`、重复 `on`、`off`、`toggle`、`status`，缺 VPN、缺热点、配置写错的报错路径，以及 `VPN_DNS=off`。
- 手动删掉本模块在热点防火墙链里的规则来复现"只剩一半"：`status` 显示 `PARTIAL`，`toggle` 会重新应用，没有可用热点接口时会清理残留。这种丢失在测试手机上也真实发生过一次，我没抓到确切时刻，只在系统日志里看到规则消失前后有一次热点上游网络的重新评估。

没验证：其他机型、ROM、安卓版本，其他 VPN 客户端，USB 或蓝牙共享，IPv6 客户端（VPN 表通常没有 IPv6 默认路由，理论上会回退到 IPv4，但我没测过），以及其他内核上与安卓 BPF 热点加速的相互影响。
热点接口自动识别假定系统热点规则的优先级是 21000（AOSP 的值）。

## 安全提示

- 需要 root，会修改防火墙和路由规则。请先读一遍 `module/vpn-tether.sh`（约 189 行）。
- 连上你热点的人都能用你的 VPN，请给热点设密码。
- 有的 VPN 服务不允许与其他设备共享连接，请自行确认。
- 不提供任何担保。

## 卸载

在 Magisk 里禁用或移除模块。想立刻清掉规则：再点一次 Action，或者关热点。

## 自己构建

```sh
./build.sh      # -> dist/vpn-tether-<版本>.zip
```

## 许可证

MIT，见 [LICENSE](LICENSE)。
