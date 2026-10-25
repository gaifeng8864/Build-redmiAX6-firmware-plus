#!/usr/bin/env bash
set -euo pipefail

# 仅用于指定 LiBwrt AX6 工作流，不能在路由器执行。
DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PKG="${1:?用法: apply.sh <openwrt/feeds/kiddin9/luci-app-bypass>}"
fail() { echo "ERROR: Bypass Sniffing v1: $*" >&2; exit 1; }

[[ -d "$PKG" && -f "$PKG/Makefile" ]] || fail "未找到 feed 软件包"
[[ -f "$DIR/changes.patch" ]] || fail "补丁文件不存在"

# 逐个核对上游文件 Git blob；init 必须已经经过原工作流 DNS_DIR 修正。
# 任意文件变化时立即失败，避免悄悄覆盖上游更新。
check_blob() {
    local file="$1" expected="$2" actual
    [[ -f "$PKG/$file" && ! -L "$PKG/$file" ]] || fail "文件不存在或为链接: $file"
    actual="$(git hash-object "$PKG/$file")"
    [[ "$actual" == "$expected" ]] || fail "上游基线变化: $file (实际 $actual)"
}
check_blob 'luasrc/model/cbi/bypass/advanced.lua' '75cea1ccbd6ac358d06c4e45627eb093d3253122'
check_blob 'root/usr/share/bypass/gen_config' '5696bc9927977efda1bba6c66935eb6d5679d6cb'
check_blob 'root/etc/init.d/bypass' 'e9df4070b0a6bb7106db3d84069295f0295e09bc'

# 先校验软件包现有的 sysupgrade 配置保存声明。
grep -Fq '/etc/config/bypass' "$PKG/Makefile" || fail 'Makefile 缺少 UCI 保留声明'
grep -Fq '/etc/bypass/' "$PKG/Makefile" || fail 'Makefile 缺少规则目录保留声明'

# 写入前验证辅助文件不会覆盖上游文件，且补丁可无模糊匹配地应用。
for rel in root/usr/share/bypass/sniff_rules.lua root/usr/share/bypass/bypass-preflight.sh root/usr/share/bypass/xray-atomic-generate.sh root/lib/upgrade/keep.d/bypass-sniff-v1; do
    [[ ! -e "$PKG/$rel" && ! -L "$PKG/$rel" ]] || fail "拒绝覆盖: $rel"
done
PATCH_LOG="$(mktemp)"
trap 'rm -f "$PATCH_LOG"' EXIT
if ! patch -d "$PKG" -p1 --batch --fuzz=0 --dry-run < "$DIR/changes.patch" > "$PATCH_LOG" 2>&1; then
    cat "$PATCH_LOG" >&2
    fail '补丁预演失败'
fi
patch -d "$PKG" -p1 --batch --fuzz=0 < "$DIR/changes.patch" > "$PATCH_LOG" 2>&1 || {
    cat "$PATCH_LOG" >&2
    fail '补丁写入失败'
}

# 改后再次核对精确内容，防止偏移应用造成行为差异。
check_blob 'luasrc/model/cbi/bypass/advanced.lua' 'b8a144e4baf2e4dc14c2b7baffd16aa483805e2d'
check_blob 'root/usr/share/bypass/gen_config' 'b1ccffef2bf41a121ce23bd5a7a61e3b6b9bcb16'
check_blob 'root/etc/init.d/bypass' 'd049674ce7c1af1eb2c90c44e430913677570584'

# 附加三个已验证辅助脚本和升级保留清单，不写入节点或个人配置。
install -D -m 0644 "$DIR/sniff_rules.lua" "$PKG/root/usr/share/bypass/sniff_rules.lua"
install -D -m 0755 "$DIR/bypass-preflight.sh" "$PKG/root/usr/share/bypass/bypass-preflight.sh"
install -D -m 0755 "$DIR/xray-atomic-generate.sh" "$PKG/root/usr/share/bypass/xray-atomic-generate.sh"
install -D -m 0644 "$DIR/keep.d-bypass-sniff-v1" "$PKG/root/lib/upgrade/keep.d/bypass-sniff-v1"

sh -n "$PKG/root/etc/init.d/bypass"
sh -n "$PKG/root/usr/share/bypass/bypass-preflight.sh"
sh -n "$PKG/root/usr/share/bypass/xray-atomic-generate.sh"
[[ -s "$PKG/root/lib/upgrade/keep.d/bypass-sniff-v1" ]] || fail '升级保留清单为空'
echo 'PASS: Bypass Sniffing v1 已注入软件包'
