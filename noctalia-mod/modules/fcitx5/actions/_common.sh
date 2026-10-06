#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR/../../..
# 动作脚本共用的开头。动作是独立进程，用的是和引擎同一套 lib——不复制粘贴实现，
# 也不假装自己还在引擎里：NOCTALIA_MOD_ID / NOCTALIA_MOD_ACTION 由引擎通过环境传进来。
#
# 这里再 source 一次自己的 module.conf（module_load），所以动作读到的声明就是预检里
# 那份，不会出现"清单说一套、脚本做一套"。
set -euo pipefail

source "$NOCTALIA_MOD_ROOT/lib/common.sh"
source "$NOCTALIA_MOD_ROOT/lib/paths.sh"
source "$NOCTALIA_MOD_ROOT/lib/module-loader.sh"
source "$NOCTALIA_MOD_ROOT/lib/deploy.sh"
source "$NOCTALIA_MOD_ROOT/lib/system.sh"

module_load "${NOCTALIA_MOD_ID:?NOCTALIA_MOD_ID is not set}" || exit 1
module_is_system || {
    error "action scripts only run for system modules"
    exit 1
}

# fcitx5 通过 D-Bus controller 重载。没装输入法（或不在会话里）时静默跳过：
# 配置已经铺好了，重载只是让它立刻生效，不该把一次成功的安装变成失败。
fcitx_reload() {
    command -v busctl >/dev/null 2>&1 || return 0
    timeout 5 busctl --user --auto-start=no call org.fcitx.Fcitx5 /controller \
        org.fcitx.Fcitx.Controller1 ReloadConfig >/dev/null 2>&1 || true
    return 0
}

fcitx_reload_classicui() {
    command -v busctl >/dev/null 2>&1 || return 0
    timeout 5 busctl --user --auto-start=no call org.fcitx.Fcitx5 /controller \
        org.fcitx.Fcitx.Controller1 ReloadAddonConfig s classicui >/dev/null 2>&1 || true
    return 0
}

# 没有 rime_deployer（或没有共享方案数据）时的退路：写一份 user.yaml 记住选择。
# 已经存在的 user.yaml 不动——那是用户的文件，往里追加第二个 var: 只会让它变成坏 YAML；
# 方案没被预编译而已，fcitx5 首次启动会自己编译。
rime_remember_selection() {
    local user_yaml=$1
    [[ -f $user_yaml ]] && return 0
    printf 'var:\n  previously_selected_schema: rime_ice\n' > "$user_yaml"
}
