#!/bin/bash
#
# Copyright (c) 2019-2020 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: redmiAX-diy.sh
# Description: OpenWrt DIY redmiAX6 script (After Update feeds)
#

echo "开始 redmiAX-diy 配置……"
echo "========================="

function merge_package(){
    repo=`echo $1 | rev | cut -d'/' -f 1 | rev`
    pkg=`echo $2 | rev | cut -d'/' -f 1 | rev`
    # find package/ -follow -name $pkg -not -path "package/custom/*" | xargs -rt rm -rf
    git clone --depth=1 --single-branch $1
    mv $2 package/custom/
    rm -rf $repo
}
function drop_package(){
    find package/ -follow -name $1 -not -path "package/custom/*" | xargs -rt rm -rf
}
function merge_feed(){
    if [ ! -d "feed/$1" ]; then
        echo >> feeds.conf.default
        echo "src-git $1 $2" >> feeds.conf.default
    fi
    ./scripts/feeds update $1
    ./scripts/feeds install -a -p $1
}
rm -rf package/custom; mkdir package/custom

# 删除软件包
 #rm -rf feeds/packages/net/openss

#修改默认IP地址
sed -i 's/192.168.1.1/192.168.6.1/g' package/base-files/files/bin/config_generate

#添加额外软件包
merge_package https://github.com/kenzok8/small-package small-package/luci-app-bypass
merge_package https://github.com/kenzok8/small-package small-package/lua-neturl
merge_package https://github.com/kenzok8/small-package small-package/chinadns-ng
merge_package https://github.com/kenzok8/small-package small-package/tcping
merge_package https://github.com/kenzok8/small-package small-package/luci-theme-argon
merge_package https://github.com/kenzok8/small-package small-package/luci-app-argon-config
#git clone https://github.com/project-lede/luci-app-godproxy package/luci-app-godproxy


./scripts/feeds update -a
./scripts/feeds install -a

echo "========================="
echo " redmiAX-diy 配置完成……"
