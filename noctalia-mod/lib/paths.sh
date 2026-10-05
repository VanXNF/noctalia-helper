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

runtime_root() {
    if [[ -n ${XDG_RUNTIME_DIR:-} && -d ${XDG_RUNTIME_DIR} && -w ${XDG_RUNTIME_DIR} ]]; then
        printf '%s/noctalia-mod\n' "$XDG_RUNTIME_DIR"
    else
        printf '%s/noctalia-mod\n' "$(cache_root)/runtime"
    fi
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
