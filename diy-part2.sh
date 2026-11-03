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
# 1) mihomo 的 dns 段由 init 脚本以 overlay 形式生成。overlay 最后合并、
#    优先级高于订阅 YAML，但源码里没写 nameserver，于是运行时沿用订阅里的
#    1.1.1.1 / 8.8.8.8，墙内不可达，内置 DNS 静默返回空，
#    表现就是代理配好了却一个站都打不开。把国内可达的 DoH 注入 overlay，
#    订阅更新也冲不掉。
#
#    注意 heredoc 用的是 <<-EOF，只剥制表符不剥空格，
#    插入行的前缀必须保持两个 tab 加两个空格，否则 YAML 结构会碎。
#
SSR_INIT="feeds/helloworld/luci-app-ssr-plus/root/etc/init.d/shadowsocksr"

if [ -f "$SSR_INIT" ]; then
	if grep -q 'enhanced-mode: redir-host' "$SSR_INIT" && ! grep -q 'doh\.pub' "$SSR_INIT"; then
		sed -i 's|^\(\t\t  \)enhanced-mode: redir-host$|\1enhanced-mode: redir-host\n\1nameserver:\n\1- https://doh.pub/dns-query\n\1- https://dns.alidns.com/dns-query|' "$SSR_INIT"
		echo "[diy] ssr-plus overlay: nameserver -> doh.pub / alidns"
	fi

	# 未配置 DNS 模式时默认走 mihomo 内置 DNS(7)，而不是 dns2tcp(1)
	sed -i 's|dns_mode="$(uci_get_by_type global pdnsd_enable 0)"|dns_mode="$(uci_get_by_type global pdnsd_enable 7)"|' "$SSR_INIT"
	echo "[diy] ssr-plus dns_mode default -> 7"
fi

# 2) 软件流量分载与 tproxy 结构性冲突：已建立的连接绕过 netfilter，
#    tproxy 收不到包，表现为有时候能上、有时候不能上。
if grep -q '^CONFIG_PACKAGE_TURBOACC_INCLUDE_FLOW_OFFLOADING=y' .config; then
	sed -i 's|^CONFIG_PACKAGE_TURBOACC_INCLUDE_FLOW_OFFLOADING=y|# CONFIG_PACKAGE_TURBOACC_INCLUDE_FLOW_OFFLOADING is not set|' .config
	echo "[diy] turboacc software flow offload disabled"
fi

# 3) GitHub 提交的文件默认 644，uci-defaults 脚本需要可执行位
if [ -d files/etc/uci-defaults ]; then
	chmod +x files/etc/uci-defaults/*
	echo "[diy] uci-defaults chmod +x"
fi
