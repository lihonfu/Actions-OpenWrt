#!/bin/bash
# OpenWrt DIY script part 2 (P3TERX/Actions-OpenWrt template).
# Runs inside the source tree, after the feeds have been installed.

# The pending-6.12 nft_flow_offload backport in coolsnowwolf/lede uses
# line-number-only hunks, so the 6.12.y flowtable rework made them land
# inside nf_flow_table_init() and broke the kernel build. Swap in the
# regenerated copies kept in kernel-patches/.
if grep -q '^@@ -668,0 +669,17 @@' target/linux/generic/pending-6.12/700-netfilter-nft_flow_offload-handle-netdevice-events-f.patch; then
	cp "$GITHUB_WORKSPACE/kernel-patches/700-netfilter-nft_flow_offload-handle-netdevice-events-f.patch" target/linux/generic/pending-6.12/700-netfilter-nft_flow_offload-handle-netdevice-events-f.patch
	cp "$GITHUB_WORKSPACE/kernel-patches/700b-netfilter-nft_flow_offload-remove-netdevice-events.patch" target/linux/generic/pending-6.12/700b-netfilter-nft_flow_offload-remove-netdevice-events.patch
	echo "Replaced stale netfilter patch"
fi

# Linux 6.12.114 renamed struct net_device.netns_local to netns_immutable, so
# the mac80211 backport patch that still uses netns_local no longer compiles.
if grep -q 'LINUX_VERSION_IS_GEQ(6,15,0)' package/kernel/mac80211/patches/build/210-wireless_netns_local_backport.patch; then
	sed -i 's/LINUX_VERSION_IS_GEQ(6,15,0)/LINUX_VERSION_IS_GEQ(6,13,0) || LINUX_VERSION_CODE >= KERNEL_VERSION(6,12,114)/g' package/kernel/mac80211/patches/build/210-wireless_netns_local_backport.patch
	echo "Adapted mac80211 netns patch for linux 6.12.114"
fi

#
# ---- SSR Plus+ DNS 修正 ----
#
# 背景：pdnsd_enable 不是 pdnsd 开关，是 DNS 模式选择器。
#   1=dns2tcp(需代理先起，启动期自锁) 4=mosdns(未编译) 6=chinadns-ng(未编译)
#   7=mihomo 内置 DNS，不依赖外部二进制或墙外上游 —— 只有它稳。
# 主节点类型是 clash，落在 supports_builtin_dns 的 clash|tuic|v2ray|ss 名单内，
# 所以模式 7 不会被回退。
#
SSR_PKG="feeds/helloworld/luci-app-ssr-plus"
SSR_INIT="$SSR_PKG/root/etc/init.d/shadowsocksr"
SSR_CFG="$SSR_PKG/root/usr/share/shadowsocksr/shadowsocksr.config"

# 1) mihomo 内置 DNS 的 nameserver。
#    init 脚本用 heredoc 往 overlay 追加 dns: 段，只写了 enable/enhanced-mode/
#    listen/ipv6，没写 nameserver，于是运行时沿用订阅 YAML 里的 1.1.1.1 / 8.8.8.8
#    DoH —— 墙内不可达，mihomo DNS 静默返回 "No answer"。
#    overlay 最后合并，优先级高于订阅 YAML，注入进去订阅更新也冲不掉。
#    注意 <<-EOF 只剥制表符不剥空格，前缀必须保持「两个 tab + 两个空格」。
if [ -f "$SSR_INIT" ]; then
	if grep -q 'enhanced-mode: redir-host' "$SSR_INIT" && ! grep -q 'doh\.pub' "$SSR_INIT"; then
		sed -i 's|^\(\t\t  \)enhanced-mode: redir-host$|\1enhanced-mode: redir-host\n\1nameserver:\n\1- https://doh.pub/dns-query\n\1- https://dns.alidns.com/dns-query|' "$SSR_INIT"
	fi
	if grep -q 'https://doh.pub/dns-query' "$SSR_INIT"; then
		echo "[diy] ssr-plus nameserver -> doh.pub / alidns"
	else
		echo "[diy] WARN: nameserver injection did not land"
	fi

	# 2) 缺项时的默认模式。661 行 dns_mode 决定 dns.enable，
	#    1308 行 ssrplus_dns 决定 pdnsd_enable_flag。只改一处会让两者不一致：
	#    dns.enable=true 但没人负责启动/指向 DNS，比原来更糟。必须一起改。
	sed -i 's|uci_get_by_type global pdnsd_enable 0|uci_get_by_type global pdnsd_enable 7|g' "$SSR_INIT"
	if [ "$(grep -c 'uci_get_by_type global pdnsd_enable 7' "$SSR_INIT")" -ge 2 ]; then
		echo "[diy] ssr-plus unset fallback -> 7 (both read points)"
	else
		echo "[diy] WARN: dns mode fallback patched fewer than 2 places"
	fi
fi

# 3) 新装或 reset 时的默认配置（reset() 直接 cp 这个文件）
if [ -f "$SSR_CFG" ]; then
	sed -i "s|^\([[:space:]]*option pdnsd_enable \)'1'\$|\1'7'|" "$SSR_CFG"
	if grep -q "option pdnsd_enable '7'" "$SSR_CFG"; then
		echo "[diy] default pdnsd_enable -> 7"
	else
		echo "[diy] WARN: default pdnsd_enable not patched"
	fi
fi

# 4) 软件流量分载与 tproxy 结构性冲突：已建立的连接绕过 netfilter，
#    tproxy 收不到包，表现为有时候能上、有时候不能上。
if grep -q '^CONFIG_PACKAGE_TURBOACC_INCLUDE_FLOW_OFFLOADING=y' .config; then
	sed -i 's|^CONFIG_PACKAGE_TURBOACC_INCLUDE_FLOW_OFFLOADING=y|# CONFIG_PACKAGE_TURBOACC_INCLUDE_FLOW_OFFLOADING is not set|' .config
	echo "[diy] turboacc software flow offload disabled"
fi

# 5) GitHub 提交的文件默认 644，uci-defaults 脚本需要可执行位
if [ -d files/etc/uci-defaults ]; then
	chmod +x files/etc/uci-defaults/*
	echo "[diy] uci-defaults chmod +x"
fi
