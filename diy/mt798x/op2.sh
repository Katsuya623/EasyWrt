#!/bin/bash
#=================================================
# DaoDao's script
#=================================================             


##
echo -e "\nmsgid \"Control\"" >> feeds/luci/modules/luci-base/po/zh_Hans/base.po
echo -e "msgstr \"控制\"" >> feeds/luci/modules/luci-base/po/zh_Hans/base.po

echo -e "\nmsgid \"NAS\"" >> feeds/luci/modules/luci-base/po/zh_Hans/base.po
echo -e "msgstr \"网络存储\"" >> feeds/luci/modules/luci-base/po/zh_Hans/base.po


##配置IP
sed -i 's/192.168.1.1/192.168.2.1/g' package/base-files/files/bin/config_generate

##
rm -rf ./feeds/extraipk/theme/luci-theme-argon-18.06
rm -rf ./feeds/extraipk/theme/luci-app-argon-config-18.06
rm -rf ./feeds/extraipk/theme/luci-theme-design
rm -rf ./feeds/extraipk/theme/luci-theme-edge
rm -rf ./feeds/extraipk/theme/luci-theme-ifit
rm -rf ./feeds/extraipk/theme/luci-theme-opentopd
rm -rf ./feeds/extraipk/theme/luci-theme-neobird

rm -rf ./package/feeds/extraipk/luci-theme-argon-18.06
rm -rf ./package/feeds/extraipk/luci-app-argon-config-18.06
rm -rf ./package/feeds/extraipk/theme/luci-theme-design
rm -rf ./package/feeds/extraipk/theme/luci-theme-edge
rm -rf ./package/feeds/extraipk/theme/luci-theme-ifit
rm -rf ./package/feeds/extraipk/theme/luci-theme-opentopd
rm -rf ./package/feeds/extraipk/theme/luci-theme-neobird


##取消bootstrap为默认主题
sed -i '/set luci.main.mediaurlbase=\/luci-static\/bootstrap/d' feeds/luci/themes/luci-theme-bootstrap/root/etc/uci-defaults/30_luci-theme-bootstrap
sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile
sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci-nginx/Makefile

##更改主机名
sed -i "s/hostname='.*'/hostname='EasyWrt'/g" package/base-files/files/bin/config_generate

##加入作者信息
sed -i "s/DISTRIB_DESCRIPTION='*.*'/DISTRIB_DESCRIPTION='EasyWrt-$(date +%Y%m%d)'/g"  package/base-files/files/etc/openwrt_release
sed -i "s/DISTRIB_REVISION='*.*'/DISTRIB_REVISION=' By DaoDao'/g" package/base-files/files/etc/openwrt_release
cp -af feeds/extraipk/patch/diy/banner-easy  package/base-files/files/etc/banner

sed -i "2iuci set istore.istore.channel='easy_daodao'" package/emortal/default-settings/files/99-default-settings
sed -i "3iuci commit istore" package/emortal/default-settings/files/99-default-settings


##WiFi
sed -i "s/MT7986_AX6000_2.4G/EasyWrt-2.4G/g" package/mtk/drivers/wifi-profile/files/mt7986/mt7986-ax6000.dbdc.b0.dat
sed -i "s/MT7986_AX6000_5G/EasyWrt-5G/g" package/mtk/drivers/wifi-profile/files/mt7986/mt7986-ax6000.dbdc.b1.dat

sed -i "s/MT7981_AX3000_2.4G/EasyWrt-2.4G/g" package/mtk/drivers/wifi-profile/files/mt7981/mt7981.dbdc.b0.dat
sed -i "s/MT7981_AX3000_5G/EasyWrt-5G/g" package/mtk/drivers/wifi-profile/files/mt7981/mt7981.dbdc.b1.dat

##New WiFi
sed -i "s/ImmortalWrt-2.4G/EasyWrt-2.4G/g" package/mtk/applications/mtwifi-cfg/files/mtwifi.sh
sed -i "s/ImmortalWrt-5G/EasyWrt-5G/g" package/mtk/applications/mtwifi-cfg/files/mtwifi.sh


##FQ全部调到VPN菜单
sed -i 's/services/vpn/g' package/feeds/luci/luci-app-ssr-plus/luasrc/controller/*.lua
sed -i 's/services/vpn/g' package/feeds/luci/luci-app-ssr-plus/luasrc/model/cbi/shadowsocksr/*.lua
sed -i 's/services/vpn/g' package/feeds/luci/luci-app-ssr-plus/luasrc/view/shadowsocksr/*.htm

sed -i 's/services/vpn/g' package/feeds/luci/luci-app-passwall/luasrc/controller/*.lua
sed -i 's/services/vpn/g' package/feeds/luci/luci-app-passwall/luasrc/passwall/*.lua
sed -i 's/services/vpn/g' package/feeds/luci/luci-app-passwall/luasrc/model/cbi/passwall/client/*.lua
sed -i 's/services/vpn/g' package/feeds/luci/luci-app-passwall/luasrc/model/cbi/passwall/server/*.lua
sed -i 's/services/vpn/g' package/feeds/luci/luci-app-passwall/luasrc/view/passwall/app_update/*.htm
sed -i 's/services/vpn/g' package/feeds/luci/luci-app-passwall/luasrc/view/passwall/socks_auto_switch/*.htm
sed -i 's/services/vpn/g' package/feeds/luci/luci-app-passwall/luasrc/view/passwall/global/*.htm
sed -i 's/services/vpn/g' package/feeds/luci/luci-app-passwall/luasrc/view/passwall/haproxy/*.htm
sed -i 's/services/vpn/g' package/feeds/luci/luci-app-passwall/luasrc/view/passwall/log/*.htm
sed -i 's/services/vpn/g' package/feeds/luci/luci-app-passwall/luasrc/view/passwall/node_list/*.htm
sed -i 's/services/vpn/g' package/feeds/luci/luci-app-passwall/luasrc/view/passwall/rule/*.htm
sed -i 's/services/vpn/g' package/feeds/luci/luci-app-passwall/luasrc/view/passwall/server/*.htm

sed -i 's/services/vpn/g' package/feeds/extraipk/luci-app-passwall2/luasrc/controller/*.lua
sed -i 's/services/vpn/g' package/feeds/extraipk/luci-app-passwall2/luasrc/passwall2/*.lua
sed -i 's/services/vpn/g' package/feeds/extraipk/luci-app-passwall2/luasrc/model/cbi/passwall2/client/*.lua
sed -i 's/services/vpn/g' package/feeds/extraipk/luci-app-passwall2/luasrc/model/cbi/passwall2/server/*.lua
sed -i 's/services/vpn/g' package/feeds/extraipk/luci-app-passwall2/luasrc/view/passwall2/app_update/*.htm
sed -i 's/services/vpn/g' package/feeds/extraipk/luci-app-passwall2/luasrc/view/passwall2/socks_auto_switch/*.htm
sed -i 's/services/vpn/g' package/feeds/extraipk/luci-app-passwall2/luasrc/view/passwall2/global/*.htm
sed -i 's/services/vpn/g' package/feeds/extraipk/luci-app-passwall2/luasrc/view/passwall2/haproxy/*.htm
sed -i 's/services/vpn/g' package/feeds/extraipk/luci-app-passwall2/luasrc/view/passwall2/log/*.htm
sed -i 's/services/vpn/g' package/feeds/extraipk/luci-app-passwall2/luasrc/view/passwall2/node_list/*.htm
sed -i 's/services/vpn/g' package/feeds/extraipk/luci-app-passwall2/luasrc/view/passwall2/rule/*.htm
sed -i 's/services/vpn/g' package/feeds/extraipk/luci-app-passwall2/luasrc/view/passwall2/server/*.htm

sed -i 's/services/vpn/g' package/feeds/luci/luci-app-vssr/luasrc/controller/*.lua
sed -i 's/services/vpn/g' package/feeds/luci/luci-app-vssr/luasrc/model/cbi/vssr/*.lua
sed -i 's/services/vpn/g' package/feeds/luci/luci-app-vssr/luasrc/view/vssr/*.htm

sed -i 's/services/vpn/g' package/feeds/luci/luci-app-openclash/luasrc/controller/*.lua
sed -i 's/services/vpn/g' package/feeds/luci/luci-app-openclash/luasrc/*.lua
sed -i 's/services/vpn/g' package/feeds/luci/luci-app-openclash/luasrc/model/cbi/openclash/*.lua
sed -i 's/services/vpn/g' package/feeds/luci/luci-app-openclash/luasrc/view/openclash/*.htm

sed -i 's/services/vpn/g' package/feeds/extraipk/luci-app-bypass/luasrc/controller/*.lua
sed -i 's/services/vpn/g' package/feeds/extraipk/luci-app-bypass/luasrc/model/cbi/bypass/*.lua
sed -i 's/services/vpn/g' package/feeds/extraipk/luci-app-bypass/luasrc/view/bypass/*.htm


## WiFi 兼容性与性能优化（CT3003 专用）
# --- 2.4G ---
if [ -f "package/mtk/drivers/wifi-profile/files/mt7981/mt7981.dbdc.b0.dat" ]; then
    DAT_B0="package/mtk/drivers/wifi-profile/files/mt7981/mt7981.dbdc.b0.dat"
    # 2.4G 频宽 20MHz，提升 IoT 设备兼容性
    sed -i 's/BandWidth=2.4G_40/BandWidth=2.4G_20/g' "$DAT_B0" 2>/dev/null || true
    # 禁用 2.4G MU-OFDMA（DL+UL），避免旧设备连接异常
    sed -i 's/MuOfdmaDlEnable=1/MuOfdmaDlEnable=0/g' "$DAT_B0" 2>/dev/null || true
    sed -i 's/MuOfdmaUlEnable=1/MuOfdmaUlEnable=0/g' "$DAT_B0" 2>/dev/null || true
fi

# --- 5G ---
if [ -f "package/mtk/drivers/wifi-profile/files/mt7981/mt7981.dbdc.b1.dat" ]; then
    DAT_B1="package/mtk/drivers/wifi-profile/files/mt7981/mt7981.dbdc.b1.dat"
    # 5G 频宽 80MHz（HE80），千兆宽带协商 1.2Gbps 已足够
    # HE160 在多 AP 漫游场景下信道无法错开，同频干扰严重
    # HE80 允许相邻 AP 使用不同信道组（ch36 vs ch149），零干扰零降速漫游
    # 保持 BandWidth=5G_80 不改，uci-defaults 中 htmode=HE80 与此一致
    # 禁用 5G MU-OFDMA（DL+UL），与部分手机浏览器兼容性冲突
    sed -i 's/MuOfdmaDlEnable=1/MuOfdmaDlEnable=0/g' "$DAT_B1" 2>/dev/null || true
    sed -i 's/MuOfdmaUlEnable=1/MuOfdmaUlEnable=0/g' "$DAT_B1" 2>/dev/null || true
fi

## 5G 信道固定 ch36（非 DFS），避免 vht80_channel_group invalid ch_band 0 驱动报错
# 修改 wireless uci defaults 使 5G 默认信道为 36
if [ -f "package/mtk/drivers/wifi-profile/files/mt7981/mt7981.dbdc.b1.dat" ]; then
    sed -i 's/Channel=0/Channel=36/g' package/mtk/drivers/wifi-profile/files/mt7981/mt7981.dbdc.b1.dat 2>/dev/null || true
fi


## === CT3003 运行时优化（打包进固件） ===
# 1. uci-defaults：首次启动时执行（DNS/IPv6/WiFi），执行后自动删除
if [ -f "../diy/mt798x/ct3003-uci-defaults" ]; then
    cp -f ../diy/mt798x/ct3003-uci-defaults package/base-files/files/etc/uci-defaults/99-ct3003-optimize
    chmod +x package/base-files/files/etc/uci-defaults/99-ct3003-optimize
fi

# 2. rc.local：每次启动执行（RPS多核/IPv6 forwarding/删全局IPv6）
if [ -f "../diy/mt798x/ct3003-rc-local" ]; then
    cp -f ../diy/mt798x/ct3003-rc-local package/base-files/files/etc/rc.local
    chmod +x package/base-files/files/etc/rc.local
fi

# 3. firewall.user：防火墙启动时执行（REJECT IPv6 FORWARD）
if [ -f "../diy/mt798x/ct3003-firewall-user" ]; then
    cp -f ../diy/mt798x/ct3003-firewall-user package/base-files/files/etc/firewall.user
    chmod +x package/base-files/files/etc/firewall.user
fi

