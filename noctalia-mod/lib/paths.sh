# shellcheck shell=bash
# XDG locations and target path checks.

project_root() {
    printf '%s\n' "${NOCTALIA_MOD_ROOT:?NOCTALIA_MOD_ROOT is not set}"
}

home_dir() {
    printf '%s\n' "${HOME:?HOME is not set}"
}

config_root() {
    printf '%s\n' "${XDG_CONFIG_HOME:-$(home_dir)/.config}"
}

state_root() {
    printf '%s\n' "${XDG_STATE_HOME:-$(home_dir)/.local/state}/noctalia-mod"
}

cache_root() {
    printf '%s\n' "${XDG_CACHE_HOME:-$(home_dir)/.cache}/noctalia-mod"
}

# 用户预设（PLAN §4）：用户手编、值得自己备份的内容，所以归 config 而不是 state
# ——state 放的是账本、快照、锁这类机器状态。
preset_root() {
    printf '%s/noctalia-mod/presets\n' "$(config_root)"
}

preset_user_dir() {
    local module=${1-} name=${2-}
    is_safe_identifier "$module" && is_safe_identifier "$name" || return 1
    printf '%s/%s/%s\n' "$(preset_root)" "$module" "$name"
}

# XDG 图片目录。`xdg-user-dir` 不存在、超时或答不出绝对路径时回退 `$HOME/Pictures`。
# LC_ALL=C 是有意的：输出必须与 locale 无关，否则中文 locale 下拿到的是"图片"那一份，
# 而这个值要写进部署后的配置文件（PLAN §4 的 @XDG_PICTURES@ 占位符）。
pictures_dir() {
    local dir=''
    dir=$(LC_ALL=C timeout 5 xdg-user-dir PICTURES 2>/dev/null) || dir=''
    [[ -n $dir && $dir == /* ]] || dir="$(home_dir)/Pictures"
    printf '%s\n' "$dir"
}

module_root() {
    printf '%s/modules/%s\n' "$(project_root)" "$1"
}

safe_target_path() {
    local relative=$1 root target
    is_safe_relative_path "$relative" || {
        error "unsafe module target: $relative"
        return 1
    }
    root=$(config_root)
    target="$root/$relative"
    case $target in
        "$root"/*) printf '%s\n' "$target" ;;
        *) error "target escapes configuration root: $relative"; return 1 ;;
    esac
}

ensure_project_dirs() {
    mkdir -p "$(config_root)" "$(state_root)/modules" "$(state_root)/snapshots" "$(cache_root)"
}
