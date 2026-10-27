#!/bin/bash
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part2.sh
# Description: OpenWrt DIY script part 2 (After Update feeds)
#
# Copyright (c) 2019-2024 P3TERX <https://p3terx.com>
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

# Fix the stale nft_flow_offload backport for the 6.12 kernel tree: the
# upstream hunks carry no context, so the 6.12.y flowtable rework made them
# land inside nf_flow_table_init() and broke the kernel build.
PD="target/linux/generic/pending-6.12"
BP="$PD/700-netfilter-nft_flow_offload-handle-netdevice-events-f.patch"
KS="$GITHUB_WORKSPACE/kernel-patches"
if [ -f "$BP" ] && grep -q '^@@ -668,0 +669,17 @@' "$BP"; then
	cp "$KS/700-netfilter-nft_flow_offload-handle-netdevice-events-f.patch" "$BP"
	cp "$KS/700b-netfilter-nft_flow_offload-remove-netdevice-events.patch" "$PD/700b-netfilter-nft_flow_offload-remove-netdevice-events.patch"
	echo "Replaced stale netfilter patch"
elif [ -f "$BP" ]; then
	echo "Netfilter patch already updated upstream, keeping it"
else
	echo "Netfilter patch not present, skipping"
fi