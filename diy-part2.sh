#!/bin/bash
# OpenWrt DIY script part 2 (P3TERX/Actions-OpenWrt template).
# Runs inside the source tree, after the feeds have been installed.
#
# 硬失败约定：凡是「DNS 修复必须落地」的检查，失败一律 exit 1。
# 上游 helloworld / lede 一旦漂移，sed 会静默不匹配；如果只 echo WARN，
# 固件照样编译成功（绿灯），但修复已经丢了 —— 那种假成功比编译失败贵得多。
# 工作流用 bash -e 执行本脚本，exit 1 会让 Load custom configuration 这一步直接红掉。

fail() {
	echo "[diy] FATAL: $*"
	exit 1
}

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
UCI_DEF="files/etc/uci-defaults"

# 下面这些是修复的物理载体，缺一个都等于修复丢失 —— 必须响亮失败。
[ -f "$SSR_INIT" ] || fail "$SSR_INIT 不存在（helloworld 目录结构变了，或 feed 被移除）"
[ -f "$SSR_CFG" ] || fail "$SSR_CFG 不存在（默认配置模板被改名或移走）"
[ -f "$UCI_DEF/zz-ssrplus-dns" ] || fail "$UCI_DEF/zz-ssrplus-dns 不存在（刷机兜底钩子丢了）"

# 1) mihomo 内置 DNS 的 nameserver。
#    init 脚本用 heredoc 往 overlay 追加 dns: 段，只写了 enable/enhanced-mode/
#    listen/ipv6，没写 nameserver，于是运行时沿用订阅 YAML 里的 1.1.1.1 / 8.8.8.8
#    DoH —— 墙内不可达，mihomo DNS 静默返回 "No answer"。
#    overlay 最后合并，优先级高于订阅 YAML，注入进去订阅更新也冲不掉。
#    注意 <<-EOF 只剥制表符不剥空格，前缀必须保持「两个 tab + 两个空格」。
if grep -q 'enhanced-mode: redir-host' "$SSR_INIT" && ! grep -q 'doh\.pub' "$SSR_INIT"; then
	sed -i 's|^\(\t\t  \)enhanced-mode: redir-host$|\1enhanced-mode: redir-host\n\1nameserver:\n\1- https://doh.pub/dns-query\n\1- https://dns.alidns.com/dns-query|' "$SSR_INIT"
fi
grep -q 'https://doh.pub/dns-query' "$SSR_INIT" || fail "nameserver 注入失败：init 脚本里 enhanced-mode 行格式变了，锚点 \`^「两个tab两个空格」enhanced-mode: redir-host$\` 不再匹配"
echo "[diy] ssr-plus nameserver -> doh.pub / alidns"

# 2) 缺项时的默认模式。661 行 dns_mode 决定 dns.enable，
#    1308 行 ssrplus_dns 决定 pdnsd_enable_flag。只改一处会让两者不一致：
#    dns.enable=true 但没人负责启动/指向 DNS，比原来更糟。必须一起改。
sed -i 's|uci_get_by_type global pdnsd_enable 0|uci_get_by_type global pdnsd_enable 7|g' "$SSR_INIT"
# 注意 || true：工作流是 bash -e，而 grep -c 无匹配时退出码为 1，
# 直接赋值会让脚本在打印诊断信息之前就静默中止。
n_reads="$(grep -c 'uci_get_by_type global pdnsd_enable 7' "$SSR_INIT" || true)"
[ "$n_reads" -ge 2 ] || fail "pdnsd_enable 默认值只改到 $n_reads 处（期望 >=2），上游读取点数量变了"
echo "[diy] ssr-plus unset fallback -> 7 ($n_reads read points)"

# 3) 新装或 reset 时的默认配置（reset() 直接 cp 这个文件）
sed -i "s|^\([[:space:]]*option pdnsd_enable \)'1'\$|\1'7'|" "$SSR_CFG"
grep -q "option pdnsd_enable '7'" "$SSR_CFG" || fail "shadowsocksr.config 里 option pdnsd_enable '1' 没改成 '7'（默认值格式变了）"
echo "[diy] default pdnsd_enable -> 7"

# 4) GitHub 提交的文件默认 644，uci-defaults 脚本需要可执行位，
#    否则刷机时根本不会执行，pdnsd_enable 不会兜底。
chmod +x "$UCI_DEF"/*
echo "[diy] uci-defaults chmod +x"

#
# 注：这里原本还有一段「关闭 turboacc software flow offload」的 sed，
# 已于 2026-11-04 删除 —— 实测 luci-app-turboacc 不存在于 coolsnowwolf/lede
# 的 package/lean（26 个目录里没有它），也从未出现在任何 feed 安装列表、
# manifest 和 config.buildinfo 里。该包及其 TURBOACC_INCLUDE_* 子符号
# 在构建树中根本不存在，make defconfig 会静默丢弃，所以那段 sed 永不执行。
# 结论：flow offload 与 tproxy 冲突这条线索对成品固件不成立，真正的病因
# 只有 pdnsd_enable 默认值 + nameserver 污染。
#
