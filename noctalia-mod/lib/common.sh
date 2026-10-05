# shellcheck shell=bash
# Shared shell primitives. This project intentionally has no runtime dependency
# beyond Bash and the base CachyOS userland.

log() {
    printf '%s\n' "$*"
}

warn() {
    printf 'warning: %s\n' "$*" >&2
}

error() {
    printf 'error: %s\n' "$*" >&2
}

is_safe_identifier() {
    [[ $1 =~ ^[a-z0-9][a-z0-9-]*$ ]]
}

is_safe_snapshot_id() {
    [[ ${1-} =~ ^snapshot_[0-9]{8}_[0-9]{6}_[0-9]+$ ]]
}

is_safe_relative_path() {
    local path=${1-}
    [[ -n $path && $path != /* && $path != *$'\n'* && $path != *$'\r'* ]] || return 1
    local segment
    IFS='/' read -r -a _path_segments <<< "$path"
    for segment in "${_path_segments[@]}"; do
        [[ -n $segment && $segment != '.' && $segment != '..' ]] || return 1
    done
}

is_safe_package_name() {
    [[ $1 =~ ^[A-Za-z0-9@._+:-]+$ ]]
}

# 可执行程序名：不放路径分隔符，避免把 ~/.config/... 这类当成命令声明。
is_safe_command_name() {
    [[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]]
}

# 必需命令声明形如 命令:包
command_entry_name() {
    printf '%s\n' "${1%%:*}"
}

command_entry_package() {
    local entry=${1-}
    [[ $entry == *:* ]] || return 1
    printf '%s\n' "${entry#*:}"
}

is_safe_relative_glob() {
    local path=${1-} normalized
    normalized=${path//\*/x}
    normalized=${normalized//\?/x}
    is_safe_relative_path "$normalized"
}

# uid 可选：不带参数时用真实 EUID，测试可以直接传 0 验证拒绝逻辑。
require_non_root() {
    local uid=${1:-${EUID:-$(id -u)}}
    if [[ $uid -eq 0 ]]; then
        error 'do not run noctalia-mod as root'
        return 1
    fi
}

# 目标环境摘要。只报告，不阻断（PLAN §5）：目标环境之外装出来的东西大概率不能
# 用，但那是用户的选择，清单里说清楚就够了。marker 路径可覆盖，好让非 CachyOS
# 开发机能验证两个分支——这段输出不参与任何判定，所以开这个口子没有安全含义。
environment_summary() {
    if [[ -f ${NOCTALIA_MOD_CACHYOS_MARKER:-/etc/cachyos-release} ]]; then
        printf 'environment\tCachyOS detected\n'
    else
        printf 'environment\tCachyOS marker not found (first-stage target only)\n'
    fi
    command -v niri >/dev/null 2>&1 || printf 'environment\tniri is not currently on PATH\n'
    command -v noctalia >/dev/null 2>&1 || printf 'environment\tNoctalia is not currently on PATH\n'
}

contains_word() {
    local needle=$1
    shift
    local item
    for item in "$@"; do
        [[ $item == "$needle" ]] && return 0
    done
    return 1
}

join_by() {
    local separator=$1
    shift
    local out='' item
    for item in "$@"; do
        [[ -n $out ]] && out+=$separator
        out+=$item
    done
    printf '%s' "$out"
}
