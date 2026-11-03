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
# ---- SSR Plus+ DNS 淇 ----
#
# 1) mihomo 鐨?dns 娈电敱 init 鑴氭湰浠?overlay 褰㈠紡鐢熸垚銆俹verlay 鏈€鍚庡悎骞躲€?#    浼樺厛绾ч珮浜庤闃?YAML锛屼絾婧愮爜閲屾病鍐?nameserver锛屼簬鏄繍琛屾椂娌跨敤璁㈤槄閲岀殑
#    1.1.1.1 / 8.8.8.8 鈥斺€?澧欏唴涓嶅彲杈撅紝鍐呯疆 DNS 闈欓粯杩斿洖绌猴紝
#    琛ㄧ幇灏辨槸"浠ｇ悊閰嶅ソ浜嗕絾涓€涓珯閮芥墦涓嶅紑"銆傛妸鍥藉唴鍙揪鐨?DoH 娉ㄥ叆 overlay锛?#    璁㈤槄鏇存柊涔熷啿涓嶆帀銆?#
#    娉ㄦ剰 heredoc 鐢ㄧ殑鏄?<<-EOF锛屽彧鍓ュ埗琛ㄧ涓嶅墺绌烘牸锛?#    鎻掑叆琛岀殑鍓嶇紑蹇呴』淇濇寔 "涓や釜 tab + 涓や釜绌烘牸"锛屽惁鍒?YAML 缁撴瀯浼氱銆?#
SSR_INIT="feeds/helloworld/luci-app-ssr-plus/root/etc/init.d/shadowsocksr"

if [ -f "$SSR_INIT" ]; then
	if grep -q 'enhanced-mode: redir-host' "$SSR_INIT" && ! grep -q 'doh\.pub' "$SSR_INIT"; then
		sed -i 's|^\(\t\t  \)enhanced-mode: redir-host$|\1enhanced-mode: redir-host\n\1nameserver:\n\1- https://doh.pub/dns-query\n\1- https://dns.alidns.com/dns-query|' "$SSR_INIT"
		echo "[diy] ssr-plus overlay: nameserver -> doh.pub / alidns"
	fi

	# 鏈厤缃?DNS 妯″紡鏃堕粯璁よ蛋 mihomo 鍐呯疆 DNS(7)锛岃€屼笉鏄?dns2tcp(1)
	sed -i 's|dns_mode="$(uci_get_by_type global pdnsd_enable 0)"|dns_mode="$(uci_get_by_type global pdnsd_enable 7)"|' "$SSR_INIT"
	echo "[diy] ssr-plus dns_mode default -> 7"
fi

# 2) 杞欢娴侀噺鍒嗚浇涓?tproxy 缁撴瀯鎬у啿绐侊細宸插缓绔嬬殑杩炴帴缁曡繃 netfilter锛?#    tproxy 鏀朵笉鍒板寘锛岃〃鐜颁负"鏈夋椂鍊欒兘涓娿€佹湁鏃跺€欎笉鑳戒笂"銆?if grep -q '^CONFIG_PACKAGE_TURBOACC_INCLUDE_FLOW_OFFLOADING=y' .config; then
	sed -i 's|^CONFIG_PACKAGE_TURBOACC_INCLUDE_FLOW_OFFLOADING=y|# CONFIG_PACKAGE_TURBOACC_INCLUDE_FLOW_OFFLOADING is not set|' .config
	echo "[diy] turboacc software flow offload disabled"
fi

# 3) GitHub 鎻愪氦鐨勬枃浠堕粯璁?644锛寀ci-defaults 鑴氭湰闇€瑕佸彲鎵ц浣?if [ -d files/etc/uci-defaults ]; then
	chmod +x files/etc/uci-defaults/*
	echo "[diy] uci-defaults chmod +x"
fi