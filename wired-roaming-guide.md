# EasyWrt 有线回程 AP 漫游组网教程（最优实践版）

> 适用固件：EasyWrt（基于 immortalwrt-mt798x openwrt-21.02）
> 适用设备：Cetron CT3003 (MT7981) / Redmi AX6000 (MT7986)
> 方案：有线回程 + MTK 原生 802.11r/k + 纯 AP 漫游
> 设计原则：**稳定 > 兼容 > 性能**

---

## ⚠️ 重要：Dawn 在 MT7981/MT7986 上不可用

**Dawn 依赖 hostapd 的 ubus 接口**，而 MT7981/MT7986 使用 MTK 闭源驱动 `mt_wifi`，**不走标准 hostapd 框架**。Dawn 启动后持续报错 `No hostapd sockets!`，完全无法工作。

**替代方案**：使用 **MTK 驱动原生的 802.11r FT 支持**：
- dat 文件 `FtSupport=1` — 开启驱动级 802.11r 快速漫游
- dat 文件 `RRMEnable=1` — 开启 802.11k 邻居报告（已默认开启）
- UCI `ft_over_ds=1` / `rrm=1` / `wnm_disassoc_imminent=1` — netifd 将这些写入 dat 文件

MTK 原生 FtSupport 是**驱动层实现**，不需要 hostapd，兼容性和稳定性都优于 Dawn。

---

## 方案缺陷与风险

### P1 — 无主动漫游引导（无 802.11v BSS TM）

**问题**：没有 Dawn 就没有主动 BSS Transition Management Request，客户端自主决定何时漫游，可能"粘"在远处 AP。

**缓解**：
- 802.11r 仍生效：漫游时 4-way handshake 缩短到 ~50ms，丢包从 10+ 降到 1~3
- 802.11k 仍生效：AP 回复 Neighbor Report，客户端知道该往哪个 AP 漫游
- 客户端主动漫游质量因设备而异：Apple 最好，安卓 12+ 次之，老安卓最差
- 可通过 `wnm_disassoc_imminent=1` 辅助引导（MTK 驱动有限支持）

### P2 — 2.4G 频段漫游粘滞

**问题**：2.4G 穿墙强，手机容易死抱远处 AP 的 2.4G。

**缓解**：
- 2.4G 设为 20MHz 降低吸引力，5G HE80 信号够用时客户端自然选 5G
- 对只支持 2.4G 的 IoT 设备无影响（它们不漫游）

### P2 — luci-app-mtwifi-cfg 潜在冲突

**问题**：MTK 官方 WiFi 管理界面会修改 wireless 配置。

**缓解**：
- uci-defaults 在首次启动时一次性配好，后续不要在 mtwifi-cfg 界面改漫游相关参数

---

## 网络架构

```
Internet
  │
  ▼
┌─────────────────────┐
│  主路由 (CT3003)      │  192.168.2.1
│  DHCP + DNS + NAT    │  MTK FtSupport=1
│  WAN: DHCP/PPPoE     │  IGMP snooping
│  LAN: 192.168.2.0/24 │
└──────────┬──────────┘
           │
     ┌─────┴─────┐
     │  有线交换机  │
     └─┬───┬───┬─┘
       │   │   │
  ┌────┴┐ ┌┴───┐┌┴────┐
  │AP-1 │ │AP-2 ││AP-3 │  哑 AP 模式
  │CT3003│ │CT3003││CT3003│  不开 DHCP/NAT
  │.2.2 │ │.2.3 ││.2.4 │  各自管理 IP
  │ch36 │ │ch52 ││ch36 │  5G 信道错开（同频段组）
  └─────┘ └─────┘└─────┘
```

### 角色分工

| 角色 | 设备 | 职责 |
|---|---|---|
| 主路由 | CT3003 (MT7981) | PPPoE/DHCP 上网、NAT、DHCP、DNS、防火墙、IGMP snooping |
| 子 AP | CT3003 (MT7981) | WiFi 覆盖，不做路由 |

### 统一参数

| 参数 | 值 | 说明 |
|---|---|---|
| SSID (2.4G) | 自定义 | 所有 AP 相同 |
| SSID (5G) | 自定义 | 所有 AP 相同 |
| 加密 | WPA2-PSK (AES) | 兼容性最佳 |
| 密码 | 自定义 | 所有 AP 相同 |
| 子网 | 192.168.2.0/24 | 所有 AP 的 LAN 同一广播域 |
| 2.4G 频宽 | 20MHz | IoT 兼容性优先 |
| 5G 频宽 | **HE80** | 千兆已够，允许信道错开零干扰漫游 |
| 5G 信道 | ch36 / ch52 交替 | 相邻 AP 错开，零干扰，同频段组（安卓兼容） |
| IGMP snooping | 启用 | 组播精准投递 |
| MTK FtSupport | 1 | 驱动级 802.11r FT |
| MTK RRMEnable | 1 | 驱动级 802.11k 邻居报告 |

---

## 部署步骤

### 第一步：编译固件

1. Fork 项目并推送到你的 GitHub 仓库
2. 进入 Actions 页面，手动触发 `Build_mt7981` workflow
3. 等待编译完成（约 2~3 小时），下载固件

### 第二步：刷机

1. 根据设备型号选择对应固件：CT3003 → `EasyWrt-Cetron-CT3003-*.bin`
2. 通过设备原厂 Web 界面或 Breed 刷入
3. 刷机后设备自动重启，默认管理地址 `192.168.2.1`

### 第三步：逐台初始化（避免 IP 冲突）

> 重要：每次只开一台设备，设好 IP 后再开下一台！

**3.1 初始化主路由**

```
1. 只给主路由上电，网线连电脑
2. 浏览器访问 192.168.2.1
3. 设置上网方式（PPPoE 或 DHCP）
4. 设置 WiFi 密码（2.4G 和 5G 设相同密码）
5. 验证能上网
6. 确认 IGMP snooping：uci show network.lan.igmp_snooping
7. 确认 FtSupport：grep FtSupport /etc/wireless/mediatek/mt7981.dbdc.b*.dat
```

主路由**不需要改管理 IP**，保持 192.168.2.1。

**3.2 初始化子 AP**

```
1. 断开主路由的网线，只给 AP 上电
2. 电脑直连 AP，访问 192.168.2.1
3. 改管理 IP：
   网络 → 接口 → LAN → 修改
   IPv4 地址：192.168.2.2
   保存并应用
4. 关闭 DHCP：
   网络 → 接口 → LAN → DHCP 服务器 → 常规设置
   忽略接口：勾选
   保存并应用
5. 设置 WiFi 密码和 SSID（与主路由完全相同）
6. 修改 5G 信道：
   网络 → 无线 → MT7981_1_2 (5G) → 编辑
   信道：52（DFS 信道，与主路由 ch36 错开，同频段组）
   ⚠️ ch52 是 DFS 信道，AP 启动后需等 1~2 分钟雷达检测，5G 才会出来
7. 修改 2.4G 信道：
   网络 → 无线 → MT7981_1_1 (2.4G) → 编辑
   信道：6（与主路由 ch1 错开）
8. 确认 FtSupport：grep FtSupport /etc/wireless/mediatek/mt7981.dbdc.b*.dat
```

**3.3 初始化更多 AP**

| AP | 管理 IP | 5G 信道 | 2.4G 信道 |
|---|---|---|---|
| 主路由 | 192.168.2.1 | 36 | 1 |
| AP-1 | 192.168.2.2 | 52 (DFS) | 6 |
| AP-2 | 192.168.2.3 | 36 | 11 |
| AP-3 | 192.168.2.4 | 52 (DFS) | 1 |

> 5G 信道交替 ch36 / ch52（同频段组，安卓可发现），2.4G 信道交替 1 / 6 / 11
> ch52 是 DFS 信道，AP 启动需等 1~2 分钟雷达检测后 5G 才可用

### 第四步：接线

```
主路由 LAN 口 ──── 交换机
                    ├── AP-1 LAN 口
                    ├── AP-2 LAN 口
                    └── AP-3 LAN 口
```

> 子 AP 只从 **LAN 口** 接线到交换机，WAN 口留空！

### 第五步：验证

**5.1 基础连通性**

```bash
ping 192.168.2.1   # 主路由
ping 192.168.2.2   # AP-1
```

**5.2 验证 MTK 原生漫游支持**

```bash
# FtSupport 应为 1
grep FtSupport /etc/wireless/mediatek/mt7981.dbdc.b0.dat
grep FtSupport /etc/wireless/mediatek/mt7981.dbdc.b1.dat
# 期望输出：FtSupport=1

# RRMEnable 应为 1
grep RRMEnable /etc/wireless/mediatek/mt7981.dbdc.b0.dat
grep RRMEnable /etc/wireless/mediatek/mt7981.dbdc.b1.dat
# 期望输出：RRMEnable=1
```

**5.3 验证 UCI 漫游参数**

```bash
uci show wireless | grep -E "ft|rrm|wnm"
# 应看到（在 wifi-iface 段上）：
# wireless.default_MT7981_1_1.ft_over_ds='1'        (802.11r 2.4G)
# wireless.default_MT7981_1_1.ft_psk_generate_local='1'
# wireless.default_MT7981_1_1.rrm='1'               (802.11k 2.4G)
# wireless.default_MT7981_1_1.wnm_disassoc_imminent='1' (802.11v 2.4G)
# wireless.default_MT7981_1_2.ft_over_ds='1'        (802.11r 5G)
# ... 5G 同上
```

**5.4 验证 IGMP snooping**

```bash
uci show network.lan.igmp_snooping
cat /sys/devices/virtual/net/br-lan/bridge/multicast_snooping
# 应为 1
```

**5.5 确认 Dawn 已禁用**

```bash
ps | grep dawn | grep -v grep
# 应该没有输出（Dawn 不应运行）

/etc/init.d/dawn enabled && echo "Dawn enabled (BAD)" || echo "Dawn disabled (GOOD)"
```

**5.6 实测漫游**

```
1. 手机连上 5G WiFi
2. 打开连续 ping：ping 192.168.2.1 -t
3. 从一个 AP 覆盖区走到另一个 AP 覆盖区
4. 观察：
   - ping 丢包应 < 3 个（802.11r 快速漫游生效）
   - 切换后 IP 不变
   - 切换后网关不变
5. 在 LuCI → 网络 → 无线 → 关联站 中查看手机当前关联的 AP
```

---

## 故障排查

### 手机漫游时丢包严重

- 检查 FtSupport：`grep FtSupport /etc/wireless/mediatek/mt7981.dbdc.b*.dat`，应为 1
- 检查 802.11r UCI：`uci show wireless | grep ft`
- 检查 WiFi 密码和 SSID 在所有 AP 上完全一致

### 手机粘在远处 AP 不走

- MTK 原生 FT 不做主动引导，客户端自主决策
- Apple 设备漫游最积极，安卓 12+ 次之，老安卓可能需要手动切 WiFi
- 确保两台 AP 信号有**重叠区域**，否则客户端可能延迟漫游
- **安卓重要**：确保两台 AP 的 5G 信道在同一频段组（ch36~ch64），安卓不会跨频段组扫描
  - ✅ ch36 + ch52：同频段组，安卓能发现
  - ❌ ch36 + ch149：不同频段组，安卓只看到主路由

### AP 的 5G 开机后要等很久才出来

- ch52 是 DFS 信道，AP 启动时必须做雷达检测（CAC），通常 1~2 分钟
- 期间 rax0 接口存在但不会发送 beacon，手机看不到
- CAC 通过后 5G 正常工作，除非检测到雷达信号（家用极罕见）
- 如果不想等，可改用非 DFS 信道 ch36（但会与主路由同频）

### 投屏/DLNA 卡顿

- 确认 IGMP snooping + multicast_querier 都开启
- 临时方案：关闭 IGMP snooping（让组播泛洪）

### 子 AP 管理页面打不开

- 确认管理 IP 没冲突
- 确认电脑和子 AP 在同一子网
- 确认 AP 的防火墙 LAN zone input 为 ACCEPT

### 子 AP 下设备拿不到 IP

- 确认子 AP 的 DHCP 已关闭
- 确认主路由 DHCP 正常运行
- 确认子 AP 的 LAN 口接到交换机（不是 WAN 口）

### Dawn 报 "No hostapd sockets!"

- **这是正常的**。MTK 闭源驱动不走 hostapd，Dawn 无法工作。
- 解决：禁用 Dawn，使用 MTK 原生 FtSupport=1

---

## 为什么 HE80 而不是 HE160

| 对比项 | HE80 | HE160 |
|---|---|---|
| 协商速率 | 1.2 Gbps | 2.4 Gbps |
| 千兆宽带实际跑满 | 是 | 是（但上限一样） |
| 可用信道组 | ch36~ch48 **和** ch149~ch161 | **仅** ch36~ch64 |
| 相邻 AP 信道错开 | ch36 vs ch52，零干扰，同频段组 | 只能同信道组，同频干扰严重 |
| 漫游切换 | 零降速 | 可能 1~2 秒降速 |
| 兼容设备 | 所有 WiFi 6 设备 | 部分设备不支持 |

**结论**：千兆宽带下选 **HE80**。

---

## 安全建议

1. **改默认密码**：首次配置后立即修改 root 密码
2. **关闭 WAN 口 SSH**：子 AP 避免误接 WAN 口暴露 SSH
3. **WiFi 加密用 WPA2-PSK (AES)**：兼容性最佳
4. **定期更新固件**：immortalwrt-mt798x 持续更新驱动和内核

---

## 附：完整配置变更清单

| 文件 | 变更 |
|---|---|
| `diy/mt798x/ct3003-uci-defaults` | MTK FtSupport=1 + wireless 层 802.11r/k/v + IGMP snooping + 禁用 Dawn + HE80 |
| `diy/mt798x/op2.sh` | 5G 频宽从 HE160 改为 HE80 |
| `diy/mt798x/ct3003-rc-local` | RPS + IGMP snooping sysfs 强制 + 禁 IPv6 |
| `diy/mt798x/ct3003-firewall-user` | IPv6 FORWARD REJECT |

### MTK 原生漫游参数一览

| 参数 | 位置 | 值 | 说明 |
|---|---|---|---|
| FtSupport | dat 文件 | 1 | 802.11r FT（驱动层实现） |
| RRMEnable | dat 文件 | 1 | 802.11k 邻居报告 |
| ft_over_ds | UCI wifi-iface | 1 | FT over DS |
| ft_psk_generate_local | UCI wifi-iface | 1 | 本地生成 PSK |
| rrm | UCI wifi-iface | 1 | Radio Resource Measurement |
| wnm_disassoc_imminent | UCI wifi-iface | 1 | BSS Transition Management |
