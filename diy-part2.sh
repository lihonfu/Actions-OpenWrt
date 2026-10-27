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