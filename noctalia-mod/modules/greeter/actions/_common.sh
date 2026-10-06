#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR/../../..
# greeter 动作脚本共用的开头与原语。
#
# 这是唯一真正动系统的模块：写 /etc/greetd、建 /var/lib、enable greetd、把别的显示
# 管理器关掉。写入一律走 `sudo install`（内容先进私有临时文件，不经过 shell），
# 改动前先存快照 + `.noctalia-mod.bak`，失败就把已经改过的放回去——系统级动作没有
# "换一棵树"的原子性，所以回滚是它自己的责任（PLAN §11 阶段 F）。
set -euo pipefail

source "$NOCTALIA_MOD_ROOT/lib/common.sh"
source "$NOCTALIA_MOD_ROOT/lib/paths.sh"
source "$NOCTALIA_MOD_ROOT/lib/module-loader.sh"
source "$NOCTALIA_MOD_ROOT/lib/system.sh"

module_load "${NOCTALIA_MOD_ID:?NOCTALIA_MOD_ID is not set}" || exit 1
module_is_system || {
    error "action scripts only run for system modules"
    exit 1
}

# greeter 管的每个文件都按"预先状态 + 备份"两件事记在临时目录里，回滚只认那里。
# 每个文件还带一个"这是我们写的"标记：重装时不能把我们自己写的文件当成用户的原始版本
# 备份下来，否则卸载会把我们的配置"还原"回来（旧引擎有这个坑，这里堵掉）。
greeter_paths() {
    GREETER_MANAGED_PATHS=("$GREETER_CONFIG" "$GREETER_POLKIT_RULE")
    GREETER_MANAGED_NAMES=(config polkit)
    GREETER_MANAGED_MARKERS=('noctalia-greeter-session' 'org.noctalia.greeter.sync-appearance')
}

greeter_file_is_ours() {
    local path=$1 marker=$2
    [[ -f $path ]] || return 1
    grep -qF -- "$marker" "$path"
}

# 上游 CLI 报出来的会话列表里有没有 niri：有才写 `-- --session niri`。
greeter_session_argument() {
    local cli
    cli=$(system_trusted_executable "$(command -v noctalia-greeter 2>/dev/null || true)") || return 0
    timeout 10 "$cli" sessions 2>/dev/null | grep -qi 'niri' || return 0
    printf '%s\n' '-- --session niri'
}

# 谁在占着登录界面。列成白名单是为了让记录文件里只可能出现认识的名字。
greeter_conflicting_dm() {
    local dm
    for dm in "${GREETER_CONFLICTS[@]}"; do
        system_unit_enabled "$dm" && {
            printf '%s\n' "$dm"
            return 0
        }
    done
    return 1
}

# 记录文件存在但内容不认识 → 当作坏记录，拒绝继续（不能拿它去 enable 一个任意单元）。
greeter_recorded_dm() {
    local value
    [[ -e $GREETER_DM_RECORD ]] || return 1
    value=$(system_read_root_file "$GREETER_DM_RECORD") || return 1
    value=${value%%$'\n'*}
    contains_word "$value" "${GREETER_CONFLICTS[@]}" || return 1
    printf '%s\n' "$value"
}

# 把这次的预先状态存进临时目录：<name>.existed / <name>.content / <name>.backup。
greeter_capture_prestate() {
    local dir=$1 index path name
    greeter_paths
    for index in "${!GREETER_MANAGED_PATHS[@]}"; do
        path=${GREETER_MANAGED_PATHS[index]}
        name=${GREETER_MANAGED_NAMES[index]}
        if [[ -e $path ]]; then
            printf 'yes\n' > "$dir/$name.existed"
            system_read_root_file "$path" > "$dir/$name.content" || return 1
        else
            printf 'no\n' > "$dir/$name.existed"
            : > "$dir/$name.content"
        fi
        # 备份是 `cp -n`：已经有了就不覆盖，所以"这次新建的备份"只有一种情形。
        if [[ -e $path.noctalia-mod.bak ]]; then
            printf 'yes\n' > "$dir/$name.backup"
        else
            printf 'no\n' > "$dir/$name.backup"
        fi
    done
    if [[ -e $GREETER_STATE_DIR ]]; then
        printf 'yes\n' > "$dir/state.existed"
    else
        printf 'no\n' > "$dir/state.existed"
    fi
    return 0
}

greeter_create_backups() {
    local dir=$1 index path name marker
    greeter_paths
    for index in "${!GREETER_MANAGED_PATHS[@]}"; do
        path=${GREETER_MANAGED_PATHS[index]}
        name=${GREETER_MANAGED_NAMES[index]}
        marker=${GREETER_MANAGED_MARKERS[index]}
        # 已经是我们的东西就不用备份：那不是"用户的原始版本"。
        if ! greeter_file_is_ours "$path" "$marker"; then
            system_backup_root_file "$path" || return 1
        fi
        # 这一步建出来的备份要记下来：回滚时它必须一起消失，否则下次安装会以为
        # 用户的原始版本已经被存过了。
        if [[ $(cat "$dir/$name.backup") == no && -e $path.noctalia-mod.bak ]]; then
            printf 'yes\n' > "$dir/$name.backup"
        fi
    done
    return 0
}

# 回滚：把这次动过的文件放回预先状态，撤掉这次新建的备份，必要时删掉状态目录。
greeter_rollback() {
    local dir=$1 failed=0 index path name existed
    greeter_paths
    for index in "${!GREETER_MANAGED_PATHS[@]}"; do
        path=${GREETER_MANAGED_PATHS[index]}
        name=${GREETER_MANAGED_NAMES[index]}
        existed=$(cat "$dir/$name.existed" 2>/dev/null || printf 'no')
        if [[ $existed == yes ]]; then
            system_write_root_file "$dir/$name.content" "$path" 644 || failed=1
        else
            system_clear_root_file "$path" || failed=1
        fi
        if [[ $(cat "$dir/$name.backup" 2>/dev/null || printf 'no') == yes ]]; then
            system_clear_root_file "$path.noctalia-mod.bak" || failed=1
        fi
    done
    if [[ $(cat "$dir/state.existed" 2>/dev/null || printf 'no') == no ]]; then
        sudo rm -rf -- "$GREETER_STATE_DIR" || failed=1
    fi
    return "$failed"
}

# 把显示管理器放回切换之前的样子：greetd 关掉、上一个重新 enable。
greeter_restore_display_manager() {
    local previous=${1-}
    if system_unit_enabled greetd; then
        system_unit_disable greetd || return 1
    fi
    [[ -n $previous ]] || return 0
    # --force 是必须的：display-manager.service 这个别名此刻指向 greetd，
    # 不带 force 的 enable 会拒绝覆盖它。
    system_unit_enable "$previous" yes || return 1
    return 0
}
