# EasyWrt 有线回程 AP 漫游组网教程

> 适用固件：EasyWrt（基于 immortalwrt-mt798x openwrt-21.02）
> 适用设备：Cetron CT3003 (MT7981) / Redmi AX6000 (MT7986)
> 方案：有线回程 + 802.11k/v/r 纯 AP 漫游

---

## 方案缺陷与风险（先泼冷水）

在动手之前，必须了解这个方案的已知问题和局限：

### P0 — Dawn 与 MTK 闭源驱动的兼容性风险

**问题**：Dawn 依赖 hostapd 的 ubus 接口获取客户端 RSSI 和发送 BSS TM Request。MTK 闭源 WiFi 驱动（mtwifi）自带独立的 hostapd 副本，**不走标准 OpenWrt wpad 框架**。

**影响**：
- Dawn 可能无法通过标准 ubus 路径读取 MTK 驱动的客户端 RSSI 数据
- BSS Transition Management Request 可能发不出去，802.11v 主动引导失效
- 邻居报告（802.11k Neighbor Report）可能不完整

**现状**：immortalwrt-mt798x 项目中 MTK 驱动已经做了大量 ubus 适配，Dawn **大概率能工作**，但不如标准 mac80211 + wpad 方案那样 100% 可靠。

**缓解措施**：
- 部署后必须实测漫游是否生效（见后文验证方法）
- 如果 Dawn 不生效，退化为纯 802.11r 快速漫游（客户端自主决策，无主动引导），仍有基本漫游能力
- 备选方案：换用 `usteer`（更轻量，对 hostapd 接口要求更低），但牺牲 802.11v 主动引导

### P1 — 160MHz 频宽与漫游的矛盾

**问题**：160MHz 需要连续 8 个 20MHz 信道（ch36~ch64 或 ch149~ch177），这意味着：
- 5G 频段只能选 **一组** 160MHz 信道
- 所有 AP 如果都开 160MHz 且用相同信道组，**同频干扰严重**
- 如果不同 AP 用不同信道组，客户端跨信道组漫游时 160MHz 需要重新协商，可能降速到 80MHz

**影响**：漫游切换瞬间可能出现 1~2 秒的速率下降（从 2402Mbps 协商降速再升回来）

**缓解措施**：
- 相邻 AP 用不同信道组（如 AP-1 ch36~64, AP-2 ch149~177）
- 如果对漫游丝滑度要求极高，可降为 HE80（牺牲峰值速率，换零漫游降速）

### P1 — 2.4G 频段漫游粘滞

**问题**：2.4G 信号穿墙能力强，客户端经常"死抱"远处 AP 的 2.4G 不放，即使近处有 5G 信号更好的 AP。

**影响**：手机从卧室走到客厅，可能还连着卧室 AP 的 2.4G（-75dBm），而不是客厅 AP 的 5G（-50dBm），体验明显变差。

**缓解措施**：
- Dawn 的 rssi_roam 设为 -70dBm 可以主动踢掉弱信号客户端
- 但 2.4G 和 5G 之间的频段间漫游（band steering）依赖 802.11v，回到 P0 的兼容性风险
- **实用建议**：对支持 5G 的设备，在路由上关闭 2.4G 关联（通过 Dawn 的 rssi_auth 机制或客户端 MAC 白名单）

### P2 — 子 AP 管理 IP 冲突

**问题**：所有子 AP 刷同一固件，默认管理 IP 都是 192.168.2.1。首次启动时多台 AP 同时在线会 IP 冲突。

**影响**：无法通过 Web 界面管理子 AP（SSH 也会连错设备）。

**缓解措施**：见后文部署步骤中的"逐台初始化"流程。

### P2 — Dawn 多实例协调

**问题**：每台 AP 都运行独立的 Dawn 实例，它们通过 ubus/umsd 相互发现。如果某台 AP 的 Dawn 挂掉或重启，其他 AP 不会立刻感知。

**影响**：短暂漫游决策不一致（几秒~十几秒），不会断网，但可能漫游到非最优 AP。

**缓解措施**：Dawn 默认 5 秒同步间隔，影响窗口很短，家用场景可忽略。

### P2 — dnsmasq dhcpv6 仍编译在内

**问题**：config 中 `CONFIG_PACKAGE_dnsmasq_full_dhcpv6=y` 仍然启用，虽然 uci 禁用了 LAN 侧 RA/DHCPv6，但 dnsmasq 二进制仍包含 v6 代码。

**影响**：不影响功能（uci 优先），但固件体积略大。纯 cosmetic 问题。

---

## 网络架构

```
Internet
  │
  ▼
┌─────────────────────┐
│  主路由 (AX6000)      │  192.168.2.1
│  DHCP + DNS + NAT    │  开 Dawn
│  WAN: PPPoE/DHCP     │
│  LAN: 192.168.2.0/24 │
└──────────┬──────────┘
           │
     ┌─────┴─────┐
     │  有线交换机  │
     └─┬───┬───┬─┘
       │   │   │
  ┌────┴┐ ┌┴───┐┌┴────┐
  │AP-1 │ │AP-2 ││AP-3 │  哑 AP 模式
  │CT3003│ │CT3003││AX6000│  不开 DHCP/NAT
  │.2.2 │ │.2.3 ││.2.4 │  各自管理 IP
  │ch36 │ │ch149││ch36 │  5G 信道错开
  └─────┘ └─────┘└─────┘
```

### 角色分工

| 角色 | 设备推荐 | 职责 |
|---|---|---|
| 主路由 | AX6000 (MT7986) | PPPoE/_DHCP 上网、NAT、DHCP 分配、DNS、防火墙、Dawn |
| 子 AP | CT3003 (MT7981) | WiFi 覆盖、Dawn 漫游引导，不做路由 |

### 统一参数

| 参数 | 值 | 说明 |
|---|---|---|
| SSID (2.4G) | EasyWrt-2.4G | 所有 AP 相同 |
| SSID (5G) | EasyWrt-5G | 所有 AP 相同 |
| 加密 | WPA2-PSK (AES) | 所有 AP 相同，兼容性最佳 |
| 密码 | 自定义 | 所有 AP 相同 |
| 子网 | 192.168.2.0/24 | 所有 AP 的 LAN 同一广播域 |
| 2.4G 频宽 | 20MHz | IoT 兼容性优先 |
| 5G 频宽 | HE160 | 千兆宽带跑满 |
| Dawn rssi_roam | -70 dBm | 触发漫游 |
| Dawn rssi_kick | -80 dBm | 踢除弱信号 |

---

## 部署步骤

### 第一步：编译固件

1. Fork 项目并推送到你的 GitHub 仓库
2. 进入 Actions 页面，手动触发 `Build_mt7981` 和 `Build_mt7986_ax6000` 两个 workflow
3. 等待编译完成（约 2~3 小时），下载固件和 packages

### 第二步：刷机

1. 根据设备型号选择对应固件：
   - CT3003 → `EasyWrt-Cetron-CT3003-*.bin`
   - AX6000 → `EasyWrt-Redmi-AX6000-*.bin`
2. 通过设备原厂 Web 界面或 Breed 刷入
3. 刷机后设备自动重启，默认管理地址 `192.168.2.1`

### 第三步：逐台初始化（避免 IP 冲突）

> 重要：每次只开一台设备，设好 IP 后再开下一台！

**3.1 初始化主路由（AX6000）**

```
1. 只给主路由上电，网线连电脑
2. 浏览器访问 192.168.2.1
3. 设置上网方式（PPPoE 或 DHCP）
4. 设置 WiFi 密码（2.4G 和 5G 设相同密码）
5. 验证能上网
```

主路由**不需要改管理 IP**，保持 192.168.2.1。

**3.2 初始化子 AP-1（CT3003）**

```
1. 断开主路由的网线，只给 AP-1 上电
2. 电脑直连 AP-1，访问 192.168.2.1
3. 改管理 IP：
   网络 → 接口 → LAN → 修改
   IPv4 地址：192.168.2.2
   保存并应用（此时页面跳转到 192.168.2.2）
4. 关闭 DHCP：
   网络 → 接口 → LAN → DHCP 服务器 → 常规设置
   忽略接口：勾选
   保存并应用
5. 关闭 WAN（如果不需要）：
   网络 → 接口 → WAN → 删除
6. 设置 WiFi 密码（与主路由相同）
7. 修改 5G 信道：
   网络 → 无线 → mt7981_1_2 (5G) → 编辑
   信道：36（如与主路由冲突则改为 149）
   保存并应用
```

**3.3 初始化子 AP-2、AP-3...**

重复 3.2 步骤，每台分配不同 IP 和信道：

| AP | 管理 IP | 5G 信道 | 2.4G 信道 |
|---|---|---|---|
| 主路由 | 192.168.2.1 | 36 | 自动(1/6/11) |
| AP-1 | 192.168.2.2 | 149 | 自动(1/6/11) |
| AP-2 | 192.168.2.3 | 36 | 自动(1/6/11) |
| AP-3 | 192.168.2.4 | 149 | 自动(1/6/11) |

> 5G 信道交替使用 ch36 和 ch149，相邻 AP 信道错开。
> 2.4G 信道建议也手动错开：1 / 6 / 11 三选一交替。

### 第四步：接线

```
主路由 LAN 口 ──── 交换机
                    ├── AP-1 LAN 口
                    ├── AP-2 LAN 口
                    └── AP-3 LAN 口
```

> 子 AP 只从 **LAN 口** 接线到交换机，WAN 口留空！
> 如果设备有多个 LAN 口，随便用哪个都行（OpenWrt 默认所有 LAN 口在同一个桥接）。

### 第五步：验证

**5.1 基础连通性**

```bash
# 从电脑 ping 各设备管理 IP
ping 192.168.2.1   # 主路由
ping 192.168.2.2   # AP-1
ping 192.168.2.3   # AP-2

# 从手机连 WiFi 后查看获取的 IP
# 应为 192.168.2.x，网关 192.168.2.1
```

**5.2 验证 Dawn 运行**

```bash
# SSH 到任一 AP，检查 Dawn 进程
ps | grep dawn

# 查看 Dawn 与 hostapd 的连接状态
ubus call dawn get_network

# 查看邻居 AP 列表（应能看到其他 AP）
ubus call dawn get_ap_list
```

**5.3 验证漫游协议**

```bash
# 在主路由上检查 802.11r/k/v 状态
# 查看 wireless 配置
uci show wireless | grep -E "ft|rrm|wnm"

# 应看到：
# wireless.@wifi-iface[x].ft_roaming='1'     (802.11r)
# wireless.@wifi-iface[x].rrm='1'            (802.11k)
# wireless.@wifi-iface[x].wnm_disassoc_imminent='1' (802.11v)
```

**5.4 实测漫游**

```
1. 手机连上 5G WiFi
2. 打开连续 ping：ping 192.168.2.1 -t
3. 从一个 AP 覆盖区走到另一个 AP 覆盖区
4. 观察：
   - ping 丢包应 < 3 个（802.11r 快速漫游）
   - 切换后 IP 不变
   - 切换后网关不变
5. 在 LuCI → 系统 → 实时日志 中查看 dawn 相关日志
6. 在 LuCI → 网络 → 无线 → 关联站 中查看手机当前关联的 AP
```

### 第六步：Dawn 微调（可选）

如果漫游表现不理想，可调整 Dawn 参数：

| 参数 | 默认 | 更激进 | 更保守 | 说明 |
|---|---|---|---|---|
| rssi_roam | -70 | -65 | -75 | 越大越早触发漫游 |
| rssi_kick | -80 | -75 | -85 | 越大越早踢除弱客户端 |
| rssi_auth | -80 | -75 | -85 | 越大越早拒绝弱关联 |
| hostapd_sync_interval | 5 | 3 | 10 | 越小检查越频繁（CPU 略增） |

修改方法：
```bash
# SSH 到 AP
uci set dawn.@dawn[0].rssi_roam='-65'
uci commit dawn
/etc/init.d/dawn restart
```

---

## 故障排查

### 手机漫游时丢包严重

- 检查 Dawn 是否在所有 AP 上运行：`ps | grep dawn`
- 检查 802.11r 是否开启：`uci show wireless | grep ft`
- 如果 Dawn 不工作：换用 usteer（需重新编译固件）

### 手机粘在远处 AP 不走

- 确认 Dawn rssi_roam 阈值是否生效
- 尝试降低 rssi_roam 到 -65（更激进引导）
- 检查手机是否支持 802.11v：老安卓可能忽略 BSS TM Request

### 子 AP 管理页面打不开

- 确认管理 IP 没冲突
- 确认电脑和子 AP 在同一子网
- 尝试 SSH：`ssh root@192.168.2.2`

### 子 AP 下设备拿不到 IP

- 确认子 AP 的 DHCP 已关闭
- 确认主路由 DHCP 正常运行
- 确认子 AP 的 LAN 口接到交换机（不是 WAN 口）

### WiFi 密码改了但子 AP 没同步

- 每台 AP 需要单独修改 WiFi 密码
- 改完后重启 WiFi：`wifi reload`

---

## 安全建议

1. **改默认密码**：固件默认 root 密码为空或 `password`，首次配置后立即修改
2. **关闭 WAN 口 SSH**：子 AP 如果误接 WAN 口，避免暴露 SSH
3. **WiFi 加密用 WPA2-PSK (AES)**：不要用 WPA3-SAE Only，很多旧设备不兼容；WPA2/WPA3 Mixed 模式理论上兼容性更好，但部分安卓有 bug，家用 WPA2-PSK 最稳
4. **定期更新固件**：immortalwrt-mt798x 项目持续更新驱动和内核

---

## 附：配置变更清单

本次针对有线回程 AP 漫游方案修改的文件：

| 文件 | 变更 |
|---|---|
| `configs/ARM/mt798x/mt7981.config` | 启用 dawn、luci-app-dawn、MBO |
| `configs/ARM/mt798x/mt7986_ax6000.config` | 同上 |
| `diy/mt798x/ct3003-uci-defaults` | 新增 Dawn 漫游控制器 uci 配置 |
