# EasyWrt 有线回程 AP 漫游组网教程（最优实践版）

> 适用固件：EasyWrt（基于 immortalwrt-mt798x openwrt-21.02）
> 适用设备：Cetron CT3003 (MT7981) / Redmi AX6000 (MT7986)
> 方案：有线回程 + 802.11k/v/r 纯 AP 漫游
> 设计原则：**稳定 > 兼容 > 性能**

---

## 方案缺陷与风险

### P0 — Dawn 与 MTK 闭源驱动的兼容性

**问题**：Dawn 依赖 hostapd 的 ubus 接口。MTK 闭源驱动（mtwifi）自带独立 hostapd，**不走标准 wpad 框架**。

**影响**：
- BSS TM Request 可能发不出去 → 802.11v 主动引导部分失效
- 邻居报告数据可能不完整

**缓解**：
- 已开启 `use_probing=1`（主动探测客户端 RSSI），即使 802.11v 部分失效，Dawn 仍能基于信号强度做踢除决策
- 如果 Dawn 完全不工作，退化为纯 802.11r 快速漫游（客户端自主决策），仍有基本漫游能力
- 部署后**必须实测**（见验证步骤）

### P1 — 2.4G 频段漫游粘滞

**问题**：2.4G 穿墙强，手机容易死抱远处 AP 的 2.4G。

**缓解**：
- Dawn `band_steering=1` + `rssi_roam=-70` + `roam_band=5g`：引导双频客户端优先 5G
- 对只支持 2.4G 的 IoT 设备无影响（它们不漫游）

### P2 — luci-app-mtwifi-cfg 与 Dawn 潜在冲突

**问题**：MTK 官方 WiFi 管理界面和 Dawn 都会修改 wireless 配置，存在竞态。

**缓解**：
- uci-defaults 在首次启动时一次性配好，后续不要在 mtwifi-cfg 界面改漫游相关参数
- 如需调整 Dawn 参数，通过 LuCI Dawn 页面或 `uci set dawn.*` 命令

### P2 — Dawn 多实例协调

**问题**：每台 AP 独立运行 Dawn，通过 ubus 相互发现。某台重启时短暂决策不一致。

**影响**：家用场景下影响窗口 < 5 秒，可忽略。

---

## 相比上一版的改进（6 项）

| # | 改进 | 原方案 | 新方案 | 收益 |
|---|---|---|---|---|
| 1 | Dawn 完整配置 | 仅 6 个参数 | 15+ 参数 | 主动探测、频段引导、踢除超时等关键项补齐 |
| 2 | IGMP/MLD Snooping | 未启用 | 桥级 igmp_snooping + multicast_querier | 投屏/DLNA/IPTV 组播不再泛洪 |
| 3 | mDNS Reflector (avahi) | 未启用 | avahi-nodbus-daemon | 跨 AP 发现打印机/AirPlay/Chromecast |
| 4 | 5G HE80 替代 HE160 | HE160 | HE80 | 允许信道错开(ch36/ch149)，零同频干扰漫游 |
| 5 | wireless 层显式启用 802.11r/k/v | 仅靠编译开关 | uci 显式设 ft_over_ds/rrm/wnm | 确保驱动默认关闭时也能生效 |
| 6 | HE160→HE80 | 千兆需 HE160 跑满 | HE80 协商 1.2G 已超千兆 | 消除漫游降速代价，家用无感知差异 |

---

## 网络架构

```
Internet
  │
  ▼
┌─────────────────────┐
│  主路由 (AX6000)      │  192.168.2.1
│  DHCP + DNS + NAT    │  开 Dawn + avahi
│  WAN: PPPoE/DHCP     │  IGMP snooping
│  LAN: 192.168.2.0/24 │
└──────────┬──────────┘
           │
     ┌─────┴─────┐
     │  有线交换机  │  IGMP snooping 交换机更佳
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
| 主路由 | AX6000 (MT7986) | PPPoE/DHCP 上网、NAT、DHCP、DNS、防火墙、Dawn、avahi、IGMP snooping |
| 子 AP | CT3003 (MT7981) | WiFi 覆盖、Dawn 漫游引导、avahi 反射，不做路由 |

### 统一参数

| 参数 | 值 | 说明 |
|---|---|---|
| SSID (2.4G) | EasyWrt-2.4G | 所有 AP 相同 |
| SSID (5G) | EasyWrt-5G | 所有 AP 相同 |
| 加密 | WPA2-PSK (AES) | 兼容性最佳，不用 WPA3-Only |
| 密码 | 自定义 | 所有 AP 相同 |
| 子网 | 192.168.2.0/24 | 所有 AP 的 LAN 同一广播域 |
| 2.4G 频宽 | 20MHz | IoT 兼容性优先 |
| 5G 频宽 | **HE80** | 千兆已够，允许信道错开零干扰漫游 |
| 5G 信道 | ch36 / ch149 交替 | 相邻 AP 错开，零同频干扰 |
| IGMP snooping | 启用 | 组播精准投递，投屏/DLNA 不卡 |
| avahi (mDNS) | 启用 | 跨 AP 设备发现 |
| Dawn rssi_roam | -70 dBm | 触发漫游 |
| Dawn rssi_kick | -80 dBm | 踢除弱信号 |
| Dawn band_steering | 启用 | 引导优先 5G |
| Dawn use_probing | 启用 | 主动探测客户端 RSSI |

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
6. 确认 avahi 正在运行：ps | grep avahi
7. 确认 IGMP snooping：uci show network.lan.igmp_snooping
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
   网络 → 无线 → MT7981_1_2 (5G) → 编辑
   信道：149（与主路由 ch36 错开）
   保存并应用
8. 确认 Dawn 运行：ps | grep dawn
```

**3.3 初始化子 AP-2、AP-3...**

| AP | 管理 IP | 5G 信道 | 2.4G 信道 |
|---|---|---|---|
| 主路由 | 192.168.2.1 | 36 | 1 |
| AP-1 | 192.168.2.2 | 149 | 6 |
| AP-2 | 192.168.2.3 | 36 | 11 |
| AP-3 | 192.168.2.4 | 149 | 1 |

> 5G 信道交替 ch36 / ch149，2.4G 信道交替 1 / 6 / 11
> HE80 下 ch36 和 ch149 完全不重叠，零同频干扰

### 第四步：接线

```
主路由 LAN 口 ──── 交换机
                    ├── AP-1 LAN 口
                    ├── AP-2 LAN 口
                    └── AP-3 LAN 口
```

> 子 AP 只从 **LAN 口** 接线到交换机，WAN 口留空！
> 推荐使用支持 IGMP snooping 的交换机（千兆管理型交换机约 100 元），非必须但更优

### 第五步：验证

**5.1 基础连通性**

```bash
ping 192.168.2.1   # 主路由
ping 192.168.2.2   # AP-1
ping 192.168.2.3   # AP-2

# 从手机连 WiFi 后查看获取的 IP
# 应为 192.168.2.x，网关 192.168.2.1
```

**5.2 验证 Dawn 运行**

```bash
ps | grep dawn
ubus call dawn get_network      # Dawn 邻居发现
ubus call dawn get_ap_list      # 应看到其他 AP
ubus call dawn get_hearing_map  # 客户端信号图
```

**5.3 验证漫游协议**

```bash
uci show wireless | grep -E "ft|rrm|wnm"
# 应看到：
# wireless.@wifi-iface[x].ft_over_ds='1'        (802.11r)
# wireless.@wifi-iface[x].ft_psk_generate_local='1'
# wireless.@wifi-iface[x].rrm='1'               (802.11k)
# wireless.@wifi-iface[x].wnm_disassoc_imminent='1' (802.11v)
```

**5.4 验证 IGMP snooping**

```bash
uci show network.lan.igmp_snooping
# 应为 network.lan.igmp_snooping='1'

cat /sys/devices/virtual/net/br-lan/bridge/multicast_snooping
# 应为 1
```

**5.5 验证 mDNS 跨 AP 发现**

```
1. 手机连 AP-1 的 WiFi
2. 打开 AirPlay 设备列表（或打印 app）
3. AirPlay 设备连在 AP-2 上
4. 应能在手机上看到该设备（avahi 做了 mDNS 反射）
5. 如果看不到：检查 avahi 进程 → ps | grep avahi
```

**5.6 实测漫游**

```
1. 手机连上 5G WiFi
2. 打开连续 ping：ping 192.168.2.1 -t
3. 从一个 AP 覆盖区走到另一个 AP 覆盖区
4. 观察：
   - ping 丢包应 < 3 个（802.11r 快速漫游）
   - 切换后 IP 不变
   - 切换后网关不变
5. 在 LuCI → 网络 → 无线 → 关联站 中查看手机当前关联的 AP
6. 漫游后确认手机在 5G 频段（band_steering 生效）
```

### 第六步：Dawn 微调（可选）

| 参数 | 默认 | 更激进 | 更保守 | 说明 |
|---|---|---|---|---|
| rssi_roam | -70 | -65 | -75 | 越大越早触发漫游 |
| rssi_kick | -80 | -75 | -85 | 越大越早踢除弱客户端 |
| rssi_auth | -80 | -75 | -85 | 越大越早拒绝弱关联 |
| hostapd_sync_interval | 5 | 3 | 10 | 越小检查越频繁 |
| kick_timeout | 100 | 50 | 200 | 踢除后等待重关联的 ms |

```bash
uci set dawn.@dawn[0].rssi_roam='-65'
uci commit dawn
/etc/init.d/dawn restart
```

---

## 故障排查

### 手机漫游时丢包严重

- 检查 Dawn：`ps | grep dawn`，所有 AP 都应运行
- 检查 802.11r：`uci show wireless | grep ft`
- 检查 use_probing：`uci show dawn | grep use_probing`，应为 1

### 手机粘在远处 AP 不走

- 降低 rssi_roam 到 -65（更激进）
- 确认 band_steering=1：`uci show dawn | grep band_steering`
- 老安卓可能忽略 BSS TM Request，尝试 rssi_kick 降到 -75 强制踢

### 跨 AP 找不到 AirPlay/打印机

- 确认 avahi 运行：`ps | grep avahi`
- 确认 IGMP snooping 开启：`uci show network.lan.igmp_snooping`
- 重启 avahi：`/etc/init.d/avahi-daemon restart`

### 投屏/DLNA 卡顿

- 确认 IGMP snooping + multicast_querier 都开启
- 如果交换机不支持 IGMP snooping，组播会泛洪，考虑换管理型交换机
- 临时方案：关闭 IGMP snooping（让组播泛洪），牺牲带宽换兼容性

### 子 AP 管理页面打不开

- 确认管理 IP 没冲突
- 确认电脑和子 AP 在同一子网
- 尝试 SSH：`ssh root@192.168.2.2`

### 子 AP 下设备拿不到 IP

- 确认子 AP 的 DHCP 已关闭
- 确认主路由 DHCP 正常运行
- 确认子 AP 的 LAN 口接到交换机（不是 WAN 口）

---

## 为什么 HE80 而不是 HE160

| 对比项 | HE80 | HE160 |
|---|---|---|
| 协商速率 | 1.2 Gbps | 2.4 Gbps |
| 千兆宽带实际跑满 | 是 | 是（但上限一样） |
| 需要的信道数 | 4 个 (20MHz) | 8 个 (20MHz) |
| 可用信道组 | ch36~ch48 **和** ch149~ch161 | **仅** ch36~ch64 |
| 相邻 AP 信道错开 | ch36 vs ch149，零干扰 | 只能同信道组，同频干扰严重 |
| 漫游切换 | 零降速 | 可能 1~2 秒降速（重新协商 160MHz） |
| 兼容设备 | 所有 WiFi 6 设备 | 部分设备不支持（老 iPhone/安卓） |

**结论**：千兆宽带下 HE80 和 HE160 实际网速一样。HE160 的唯一优势是局域网内设备间传输（NAS 到电脑），但代价是漫游质量下降。家用场景选 **HE80**。

---

## 安全建议

1. **改默认密码**：首次配置后立即修改 root 密码
2. **关闭 WAN 口 SSH**：子 AP 避免误接 WAN 口暴露 SSH
3. **WiFi 加密用 WPA2-PSK (AES)**：WPA3-SAE Only 很多旧设备不兼容，WPA2/WPA3 Mixed 部分安卓有 bug
4. **定期更新固件**：immortalwrt-mt798x 持续更新驱动和内核

---

## 附：完整配置变更清单

| 文件 | 变更 |
|---|---|
| `configs/ARM/mt798x/mt7981.config` | 启用 dawn、luci-app-dawn、MBO、avahi-nodbus-daemon |
| `configs/ARM/mt798x/mt7986_ax6000.config` | 同上 |
| `diy/mt798x/ct3003-uci-defaults` | 完整 Dawn 配置 + wireless 层 802.11r/k/v + IGMP snooping + HE80 |
| `diy/mt798x/op2.sh` | 5G 频宽从 HE160 改为 HE80（删除 sed 改 160 的行） |

### Dawn 完整参数一览

| 参数 | 值 | 说明 |
|---|---|---|
| enabled | 1 | 启用 |
| rssi_roam | -70 | 触发漫游 dBm |
| rssi_kick | -80 | 踢除弱信号 dBm |
| rssi_auth | -80 | 拒绝弱关联 dBm |
| bss_transition | 1 | 802.11v BSS TM |
| neighbor_report | 1 | 802.11k 邻居报告 |
| hostapd_sync_interval | 5 | 检查间隔秒 |
| use_probing | 1 | 主动探测客户端 RSSI |
| channel_utilization | 0 | 不基于信道利用率漫游 |
| band_steering | 1 | 频段引导优先 5G |
| kick_timeout | 100 | 踢除后等待 ms |
| max_neighbor_reports | 8 | 最大邻居数 |
| roam_band | 5g | 漫游目标频段 |
