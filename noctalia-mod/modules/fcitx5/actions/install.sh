#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# 装：素材 + 雾凇拼音 + 设为默认。三步都是可重跑的，重复执行收敛。
#
# 素材（deploy）与设为默认（activate）是分开的动作，"只铺素材不动主题"走
# `noctalia-mod action fcitx5 deploy`；install 把三件一起做完，是因为用户点名要装
# 这个模块时，铺完却看不见任何变化才是更奇怪的结果。预检清单里 classicui.conf 是
# 列出来的，所以这次改动不是静默的。
source "$(dirname -- "${BASH_SOURCE[0]}")/_common.sh"

here=$(dirname -- "${BASH_SOURCE[0]}")
bash -- "$here/deploy.sh" || exit 1
bash -- "$here/rime.sh" || exit 1
bash -- "$here/activate.sh" || exit 1
exit 0
