# EasyWrt 有线回程 AP 漫游组网教程（最优实践版）

> 适用固件：EasyWrt（基于 immortalwrt-mt798x openwrt-21.02）
> 适用设备：Cetron CT3003 (MT7981) / Redmi AX6000 (MT7986)
> 方案：有线回程 + 802.11k 邻居报告 + 纯客户端自主漫游
> 设计原则：**稳定 > 兼容 > 性能**

---

## ⚠️ 重要：MT7981/MT7986 漫游方案限制

### Dawn 不可用

**Dawn 依赖 hostapd 的 ubus 接口**，而 MT7981/MT7986 使用 MTK 闭源驱动 `mt_wifi`，**不走标准 hostapd 框架**。Dawn 启动后持续报错 `No hostapd sockets!`，完全无法工作。

### 802.11r FT 也不可用（实测确认）

MTK 闭源驱动 `mt_wifi` 的 802.11r FT 实现有两个致命缺陷：

1. **R0KH-ID 使用内部 MAC** — 驱动自动生成的 R0KH-ID（如 `Ralink:91:d1:66:57:a8:71`）与实际接口 MAC 不匹配，AP 间无法互相定位 R0KH → 日志报 `R0KH unreachable!!!`
2. **PMKID 推导不正确** — 即使设了 `ft_psk_generate_local=0` + `mobility_domain=0x0001`，两端 PMKID 仍对不上 → 日志报 `The PMKID is invalid`

实测结果：

| 设备 | FtSupport=1 行为 | 结果 |
|------|-----------------|------|
| iPhone | PMKID invalid 后降级做完整 4-way 握手 | ✅ 漫游正常 |
| Redmi (MIUI13) | PMKID invalid 后反复重试 FT，7+ 次全失败 | ❌ 断连 |
| Windows (AX200) | 同 iPhone，降级 4-way | ✅ 可工作 |

**结论**：开着 FtSupport 反而让安卓设备在 FT 认证失败时反复重试导致断连，关掉后所有设备走标准 4-way 认证，反而更稳定。

### AP 侧主动干预限制

| 手段 | 结果 | 原因 |
|------|------|------|
| Dawn | ❌ 不工作 | 没有 hostapd socket |
| FtSupport=1 (802.11r) | ❌ 反而有害 | PMKID invalid + R0KH unreachable |
| KickStaRssiLow（FT 开着时） | ❌ ping-pong 死循环 | 被踢→FT重试→失败→再踢→死循环 |
| KickStaRssiLow（FT 关闭后） | ✅ **可用** | 被踢→直接4-way→连最强AP→稳定 |
| AssocReqRssiThres | ❌ 双向拒绝 | 交界区两边都拒→设备连不上任何AP |
| ForceRoamSupport | ❌ 不支持 | iwpriv "Command not Support" |

**方案：客户端自主漫游 + 802.11k 邻居报告 + KickStaRssiLow 辅助踢弱信号**

---

## 方案缺陷与缓解

### P1 — 无 FT 快速漫游（802.11r 不可用）

**问题**：关掉 FtSupport 后漫游需完整 4-way 握手，切换约 100~200ms，丢包 5~10 个。

**缓解**：
- 802.11k 仍生效：AP 回复 Neighbor Report，客户端知道该往哪个 AP 漫游
- Apple 设备漫游策略激进，几乎不受影响
- 非 Apple 设备漫游体验因设备而异（MIUI 保守，Intel 可调）

### P2 — 无主动漫游引导（无 802.11v BSS TM）

**问题**：没有主动 BSS Transition Management Request，客户端自主决定何时漫游。

**缓解**：
- Apple 设备漫游最积极，实测满意
- 安卓 12+ 部分改善，MIUI 仍保守
- 老安卓/MIUI 可能需要手动切 WiFi

### P3 — 2.4G 频段漫游粘滞

**问题**：2.4G 穿墙强，手机容易死抱远处 AP 的 2.4G。

**缓解**：
- 2.4G 设为 20MHz 降低吸引力，5G HE80 信号够用时客户端自然选 5G
- 对只支持 2.4G 的 IoT 设备无影响（它们不漫游）

### P4 — luci-app-mtwifi-cfg 潜在冲突

**缓解**：uci-defaults 在首次启动时一次性配好，后续不要在 mtwifi-cfg 界面改漫游相关参数

---

## 网络架构

```
Internet
  │
  ▼
┌─────────────────────┐
│  主路由 (CT3003)      │  192.168.2.1
│  DHCP + DNS + NAT    │  802.11k only
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
| MTK FtSupport | **0（禁用）** | 802.11r FT 在闭源驱动上有致命缺陷 |
| MTK RRMEnable | 1 | 802.11k 邻居报告（保留，帮助客户端发现AP） |
| KickStaRssiLow (5G) | **-70** | 踢弱信号设备，帮助安卓漫游（FT关闭后可用） |
| KickStaRssiLow (2.4G) | 0 | 2.4G不踢，穿墙信号强踢人风险大 |

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
6. 确认 FtSupport=0：grep FtSupport /etc/wireless/mediatek/mt7981.dbdc.b*.dat
7. 确认 RRMEnable=1：grep RRMEnable /etc/wireless/mediatek/mt7981.dbdc.b*.dat
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
8. 确认 FtSupport=0：grep FtSupport /etc/wireless/mediatek/mt7981.dbdc.b*.dat
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

**5.2 验证 FtSupport 已关闭**

```bash
grep FtSupport /etc/wireless/mediatek/mt7981.dbdc.b0.dat
grep FtSupport /etc/wireless/mediatek/mt7981.dbdc.b1.dat
# 期望输出：FtSupport=0
```

**5.3 验证 RRMEnable 已开启**

```bash
grep RRMEnable /etc/wireless/mediatek/mt7981.dbdc.b0.dat
grep RRMEnable /etc/wireless/mediatek/mt7981.dbdc.b1.dat
# 期望输出：RRMEnable=1
```

**5.4 验证 UCI 层 FT 参数已删除**

```bash
uci show wireless | grep -E "ft_|mobility|nas_id"
# 应该没有输出（FT 参数已删除）
uci show wireless | grep rrm
# 应看到 rrm='1'
```

**5.5 验证 IGMP snooping**

```bash
uci show network.lan.igmp_snooping
cat /sys/devices/virtual/net/br-lan/bridge/multicast_snooping
# 应为 1
```

**5.6 确认 Dawn 已禁用**

```bash
ps | grep dawn | grep -v grep
# 应该没有输出（Dawn 不应运行）

/etc/init.d/dawn enabled && echo "Dawn enabled (BAD)" || echo "Dawn disabled (GOOD)"
```

**5.7 实测漫游**

```
1. 手机连上 5G WiFi
2. 打开连续 ping：ping 192.168.2.1 -t
3. 从一个 AP 覆盖区走到另一个 AP 覆盖区
4. 观察：
   - iPhone：漫游积极，丢包 < 3 个
   - 安卓/MIUI：可能粘滞，需手动切 WiFi
   - 切换后 IP 不变，网关不变
5. 在 LuCI → 网络 → 无线 → 关联站 中查看手机当前关联的 AP
```

---

## 各设备漫游调优

### iPhone / iPad
- 无需任何设置，Apple 漫游策略已是最激进
- 实测满意，秒切

### Windows (Intel AX200/AX210)
- 打开 Intel PROSet/Wireless Software 或设备管理器
- 找到无线网卡 → 高级 → **漫游激进度**
- 默认值 Medium，改为 **Medium-High** 或 **High**
- 驱动版本 23.160.0.4 测试可用

### 安卓 (MIUI)
- MIUI 漫游策略非常保守，-85dBm 都不切
- **KickStaRssiLow=-70 辅助踢弱信号**：当手机信号低于 -70dBm 时 AP 主动踢掉，手机重连到信号更强的 AP
- 如果仍然粘滞 → 说明信号还高于 -70，可尝试更激进的 -65（但交界区 ping-pong 风险增加）
- 随机 MAC 不影响漫游（漫游看的是认证信息，不是 MAC）

---

## 故障排查

### 手机漫游时断连反复重试

- 检查 FtSupport 是否误开：`grep FtSupport /etc/wireless/mediatek/mt7981.dbdc.b*.dat`，应为 **0**
- 检查 UCI FT 参数是否误设：`uci show wireless | grep ft_`，应无输出
- 如果有 → 删除后重启 WiFi

### 手机粘在远处 AP 不走

- 这是客户端自主漫游的正常行为（MIUI 保守策略）
- 确保两台 AP 信号有重叠区域
- **安卓重要**：确保两台 AP 的 5G 信道在同一频段组（ch36~ch64），安卓不会跨频段组扫描
  - ✅ ch36 + ch52：同频段组，安卓能发现
  - ❌ ch36 + ch149：不同频段组，安卓只看到主路由

### AP 的 5G 开机后要等很久才出来

- ch52 是 DFS 信道，AP 启动时必须做雷达检测（CAC），通常 1~2 分钟
- 期间 rax0 接口存在但不会发送 beacon，手机看不到
- CAC 通过后 5G 正常工作

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
- 解决：禁用 Dawn

### dmesg 出现 "The PMKID is invalid" 或 "R0KH unreachable"

- 说明 FtSupport 误开了 → 立即关闭
- 修改方法：`sed -i 's/^FtSupport=1$/FtSupport=0/' /etc/wireless/mediatek/mt7981.dbdc.b*.dat`
- 然后重启 WiFi

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
| `diy/mt798x/ct3003-uci-defaults` | FtSupport=0 + 删除FT参数 + rrm=1 + KickStaRssiLow 5G=-70 + IGMP snooping + 禁用 Dawn + HE80 |
| `diy/mt798x/op2.sh` | 5G 频宽从 HE160 改为 HE80 |
| `diy/mt798x/ct3003-rc-local` | RPS + IGMP snooping sysfs 强制 + 禁 IPv6 |
| `diy/mt798x/ct3003-firewall-user` | IPv6 FORWARD REJECT |

### 漫游参数一览

| 参数 | 位置 | 值 | 说明 |
|---|---|---|---|
| FtSupport | dat 文件 | **0（禁用）** | 802.11r FT 在闭源驱动上有致命缺陷 |
| RRMEnable | dat 文件 | 1 | 802.11k 邻居报告（保留） |
| KickStaRssiLow (5G) | dat 文件 | **-70** | 踢弱信号设备，帮助安卓漫游 |
| KickStaRssiLow (2.4G) | dat 文件 | 0 | 2.4G 不踢 |
| ft_over_ds | UCI wifi-iface | 删除 | FT 参数已清除 |
| ft_psk_generate_local | UCI wifi-iface | 删除 | FT 参数已清除 |
| mobility_domain | UCI wifi-iface | 删除 | FT 参数已清除 |
| rrm | UCI wifi-iface | 1 | 802.11k 邻居报告 |
