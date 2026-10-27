#!/bin/bash
# OpenWrt DIY script part 2 (P3TERX/Actions-OpenWrt template).
# Runs inside the source tree, after feeds update.

# Fix the stale nft_flow_offload backport for the 6.12 kernel tree: the
# upstream hunks carry no context, so the 6.12.y flowtable rework made them
# land inside nf_flow_table_init() and broke the kernel build.
PD="target/linux/generic/pending-6.12"
BP="$PD/700-netfilter-nft_flow_offload-handle-netdevice-events-f.patch"
KS="$GITHUB_WORKSPACE/kernel-patches"
if [ -f ""BP" ] && grep -q '^@@ -668,0 +669,17 @@' "$BP"; then
	cp "$KS/700-netfilter-nft_flow_offload-handle-netdevice-events-f.patch" "$BP"
	cp "$KS/700b-netfilter-nft_flow_offload-remove-netdevice-events.patch" "$PD/700b-netfilter-nft_flow_offload-remove-netdevice-events.patch"
	echo "Replaced stale netfilter patch"
fi

# Linux 6.12.114 renamed struct net_device.netns_local to netns_immutable, so
# the mac80211 backport patch that still uses netns_local no longer compiles.
MP="package/kernel/mac80211/patches/build/210-wireless_netns_local_backport.patch"
if [ -f "$MP" ] && grep -q 'LINUX_VERSION_IS_GEQ(6,15,0)' "$MP"; then
	sed -i 's/LINUX_VERSION_IS_GEQ(6,15,0)/LINUX_VERSION_IS_GEQ(6,13,0) || LINUX_VERSION_CODE >= KERNEL_VERSION(6,12,114)/g' "$MP"
	echo "Adapted mac80211 netns patch for linux 6.12.114"
fi