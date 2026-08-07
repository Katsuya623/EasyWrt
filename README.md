# EasyWrt

基于 [immortalwrt-mt798x](https://github.com/nicholasgao/immortalwrt-mt798x)（OpenWrt 21.02 分支）的精简固件，专注**有线回程多 AP 漫游**场景。

---

## 特性

- **有线回程 + 802.11k/v/r 纯 AP 漫游**：Dawn 漫游控制器，支持 BSS Transition Management（802.11v）、邻居报告（802.11k）、快速漫游（802.11r）
- **IGMP/MLD Snooping**：组播精准投递，投屏/DLNA/IPTV 不泛洪
- **mDNS 跨 AP 发现**：avahi reflector，打印机/AirPlay/Chromecast 跨 AP 可见
- **IPv6 LAN 侧禁用**：规避 MT7981 hnat 不支持 IPv6 硬件 NAT 导致的安卓卡顿
- **IoT 兼容性优先**：2.4G 20MHz 频宽 + 禁用 MU-OFDMA
- **iStore 应用中心**：在线安装插件，按需扩展

## 支持设备

| 设备 | SoC | WiFi | 网口 | 推荐角色 |
|---|---|---|---|---|
| Cetron CT3003 | MT7981 (双核 A53) | Wi-Fi 6 AX3000 | 千兆 ×4 | 子 AP（哑 AP 模式） |
| Redmi AX6000 | MT7986 (四核 A53) | Wi-Fi 6 AX6000 | 2.5G ×1 + 千兆 ×3 | 主路由 |

## 网络架构

```
Internet
  │
  ▼
┌─────────────────────┐
│  主路由 (AX6000)      │  192.168.2.1
│  DHCP + DNS + NAT    │  Dawn + avahi
│  WAN: PPPoE/DHCP     │  IGMP snooping
│  LAN: 192.168.2.0/24 │
└──────────┬──────────┘
           │
     ┌─────┴─────┐
     │  有线交换机  │
     └─┬───┬───┬─┘
       │   │   │
  ┌────┴┐ ┌┴───┐┌┴────┐
  │AP-1 │ │AP-2 ││AP-3 │  哑 AP 模式
  │ch36 │ │ch149││ch36 │  5G 信道错开
  └─────┘ └─────┘└─────┘
```

所有设备**同属一个局域网**（192.168.2.0/24），子 AP 只做无线桥接，不开 DHCP/NAT。

## 默认配置

```
固件管理 IP：192.168.2.1
用户名：root
密码：为空 或 password
SSID (2.4G)：EasyWrt-2.4G
SSID (5G)：EasyWrt-5G
```

### WiFi 参数

| 频段 | 频宽 | 信道 | MU-OFDMA | 说明 |
|---|---|---|---|---|
| 2.4G | 20MHz | 1/6/11 交替 | 禁用 | IoT 兼容性优先 |
| 5G | HE80 | 36/149 交替 | 禁用 | 千兆已够，允许信道错开零干扰漫游 |

### Dawn 漫游参数

| 参数 | 值 | 说明 |
|---|---|---|
| rssi_roam | -70 dBm | 触发漫游 |
| rssi_kick | -80 dBm | 踢除弱信号 |
| rssi_auth | -80 dBm | 拒绝弱关联 |
| bss_transition | 1 | 802.11v 主动引导 |
| neighbor_report | 1 | 802.11k 邻居报告 |
| use_probing | 1 | 主动探测客户端 RSSI |
| band_steering | 1 | 引导优先 5G |
| roam_band | 5g | 漫游目标频段 |

## 编译

### GitHub Actions 自动编译

1. Fork 本仓库
2. 进入 **Actions** 页面
3. 手动触发 `Build_mt7981` 和/或 `Build_mt7986_ax6000`
4. 等待编译完成（约 2~3 小时）
5. 在 Release 中下载固件

定时编译：北京时间每周五 20:00 自动触发。

### 本地编译

```bash
# 克隆源码
git clone https://github.com/nicholasgao/immortalwrt-mt798x.git
cd immortalwrt-mt798x

# 更新 feeds
./scripts/feeds_update.sh
./scripts/feeds_install.sh

# 复制配置
cp configs/ARM/mt798x/mt7981.config .config  # CT3003
# 或
cp configs/ARM/mt798x/mt7986_ax6000.config .config  # AX6000

# 编译
make download -j$(nproc)
make -j$(nproc) V=s
```

## 刷机

| 设备 | 固件文件 | 刷入方式 |
|---|---|---|
| CT3003 | `EasyWrt-Cetron-CT3003-*.bin` | Breed 或原厂 Web |
| AX6000 | `EasyWrt-Redmi-AX6000-*.bin` | Breed 或原厂 Web |

刷机后设备自动重启，首次启动时 uci-defaults 脚本自动执行优化配置（DNS/IPv6/WiFi/Dawn），执行后脚本自动删除。

## 组网部署

详见 [有线回程组网教程](wired-roaming-guide.md)，包含：

- 6 步部署流程（编译 → 刷机 → 初始化 → 接线 → 验证 → 微调）
- 方案缺陷与风险分析
- 漫游验证方法
- 故障排查指南
- 安全建议

## 项目结构

```
├── configs/ARM/mt798x/
│   ├── mt7981.config              # CT3003 编译配置
│   └── mt7986_ax6000.config      # AX6000 编译配置
├── diy/mt798x/
│   ├── ct3003-uci-defaults        # 首次启动优化（DNS/IPv6/WiFi/Dawn/IGMP）
│   ├── ct3003-rc-local            # 每次启动优化（RPS/IPv6 forwarding）
│   ├── ct3003-firewall-user       # 防火墙规则（REJECT IPv6 FORWARD）
│   ├── op1.sh                     # 编译前脚本（源码修改）
│   └── op2.sh                     # 编译前脚本（WiFi/主题/配置注入）
├── .github/workflows/
│   ├── Build_mt7981.yml           # CT3003 编译 workflow
│   └── Build_mt7986_ax6000.yml   # AX6000 编译 workflow
├── wired-roaming-guide.md         # 组网教程
└── README.md
```

## 致谢

- [immortalwrt-mt798x](https://github.com/nicholasgao/immortalwrt-mt798x) — 固件源码
- [OpenWrt](https://openwrt.org/) — 基础框架
- [Dawn](https://github.com/berlin-open-wireless-lab/DAWN) — 802.11k/v/r 漫游控制器

## License

与上游 immortalwrt-mt798x 一致。
