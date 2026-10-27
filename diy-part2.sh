#!/bin/bash
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part2.sh
# Description: OpenWrt DIY script part 2 (After Update feeds)
#
# Copyright (c) 2019-2024 P3TERY <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

# Modify default IP
#sed -i 's/192.168.1.1/192.168.50.5/g' package/base-files/files/bin/config_generate

# Modify default theme
#sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile

# Modify hostname
#sed -i 's/OpenWrt/P3TERX-Router/g' package/base-files/files/bin/config_generate

# Fix the stale nft_flow_offload backport in the 6.12 kernel tree.
# The patch shipped by coolsnowwolf/lede uses line-number-only hunks.  The
# flowtable rework in linux 6.12.y moved that code, so the hunks landed inside
# nf_flow_table_init() and the kernel stopped compiling.  When the broken patch
# is still in the tree, replace it with a regenerated version (same change, real
# context) and add the companion patch that drops the now duplicated handler
# from nft_flow_offload.c.
PATCH_DIR="target/linux/generic/pending-6.12"
BROKEN_PATCH="$PATCH_DIR/700-netfilter-nft_flow_offload-handle-netdevice-events-f.patch"
FIXED_PATCH="$GITHUB_WORKSPACE/kernel-patches/700-netfilter-nft_flow_offload-handle-netdevice-events-f.patch"
FIXED_PATCH2="$GITHUB_WORKSPACE/kernel-patches/700b-netfilter-nft_flow_offload-remove-netdevice-events.patch"
if [ -f "$BROKEN_PATCH" ] && grep -q '^@@ -668,0 +669,17 @@' ""BROKEN_PATCH"; then
	cp "$FIXED_PATCH" "$BROKEN_PATCH"
	cp "$FIXED_PATCH2" "$PATCH_DIR/700b-netfilter-nft_flow_offload-remove-netdevice-events.patch"
	echo "Replaced stale netfilter patch: $BROKEN_PATCH"
elif [ -f ""BROKEN_PATCH" ]; then
	echo "Netfilter patch already updated upstream, keeping it: "BROKEN_PATCH"
else
	echo "Netfilter patch not present, skipping: "BROKEN_PATCH"
fi