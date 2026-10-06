#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR/../../..
# fisher 动作脚本共用的开头与所有权账本原语。
#
# 账本 `$XDG_STATE_HOME/noctalia-mod/fisher.owned`：first line `complete<TAB>0|1`，
# 之后一行一个"我们装进去的"相对路径（相对 ~/.config/fish）。
# 为什么不用引擎的模块账本：模块账本在动作成功之后才写，而 fisher 装到一半失败时
# **已经**在用户目录里留了文件——那些文件必须当场记下来，重试才能清干净。所以这份
# 账本是动作自己维护的，跟引擎的 enabled 标志是两件事。
set -euo pipefail

source "$NOCTALIA_MOD_ROOT/lib/common.sh"
source "$NOCTALIA_MOD_ROOT/lib/paths.sh"
source "$NOCTALIA_MOD_ROOT/lib/module-loader.sh"
source "$NOCTALIA_MOD_ROOT/lib/system.sh"
source "$NOCTALIA_MOD_ROOT/lib/network.sh"

module_load "${NOCTALIA_MOD_ID:?NOCTALIA_MOD_ID is not set}" || exit 1
module_is_system || {
    error "action scripts only run for system modules"
    exit 1
}

# 动作脚本改不了调用方的 shell，所以路径在这里算一次给后面用。
FISHER_DIR="$HOME/.config/fish"

fisher_record_path() {
    printf '%s/fisher.owned\n' "$(state_root)"
}

# 读账本：FISHER_COMPLETE=yes|no，FISHER_OWNED_FILES 是路径数组。
# 账本里出现白名单之外的名字就当这份账本坏了（返回 1）——宁可不卸，也不拿它当删除清单。
FISHER_COMPLETE=no
FISHER_OWNED_FILES=()

# 这两个全局由 install/status/uninstall 读，单文件静态分析看不到那些读取点，
# 所以这一个函数块里关掉"赋值了没人用"的提示。
# shellcheck disable=SC2034
fisher_load_ownership() {
    local record=$1 line relative
    FISHER_COMPLETE=no
    FISHER_OWNED_FILES=()
    [[ -f $record ]] || return 1
    while IFS= read -r line; do
        [[ -n $line ]] || continue
        if [[ $line == complete$'\t'* ]]; then
            [[ ${line#*$'\t'} == 1 ]] && FISHER_COMPLETE=yes
            continue
        fi
        relative=$line
        is_safe_relative_path "$relative" || return 1
        contains_word "$relative" "${MODULE_FISHER_MANAGED_FILES[@]}" || return 1
        FISHER_OWNED_FILES+=("$relative")
    done < "$record"
    return 0
}

fisher_write_ownership() {
    local complete=$1 record directory temp
    shift
    record=$(fisher_record_path)
    directory=$(dirname "$record")
    mkdir -p "$directory" || return 1
    temp=$(mktemp "$directory/.fisher.owned.XXXXXX") || return 1
    # 空的所有权列表是合法的（刚装到一半），所以这里用 if 而不是 `(($#)) && ...`：
    # 后者作为块里最后一句在 $# == 0 时返回 1，会把这个成功的写入判成失败（PLAN §16.4 陷阱）。
    {
        printf 'complete\t%s\n' "$complete"
        if (($#)); then
            printf '%s\n' "$@"
        fi
    } > "$temp" || {
        rm -f -- "$temp"
        return 1
    }
    mv -f -- "$temp" "$record"
}

# 白名单里此刻真实存在的文件（安装前后各取一次，差值就是这次新写进去的）。
fisher_present_files() {
    local relative
    for relative in "${MODULE_FISHER_MANAGED_FILES[@]}"; do
        [[ -f $FISHER_DIR/$relative || -L $FISHER_DIR/$relative ]] || continue
        printf '%s\n' "$relative"
    done
    return 0
}

# 部署出来的锁文件必须**逐行等于**本模块钉住的那份：用户改过就不装。
fisher_lockfile_matches() {
    local lock=$FISHER_DIR/fish_plugins line index=0
    [[ -f $lock ]] || return 1
    while IFS= read -r line; do
        [[ -n $line ]] || continue
        [[ ${MODULE_FISHER_PLUGINS[index]-} == "$line" ]] || return 1
        index=$((index + 1))
    done < "$lock"
    ((index == ${#MODULE_FISHER_PLUGINS[@]}))
}
