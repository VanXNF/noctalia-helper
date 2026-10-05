# Shared shell primitives. This project intentionally has no runtime dependency
# beyond Bash and the base CachyOS userland.

NOCTALIA_MOD_NAME='noctalia-mod'
NOCTALIA_MOD_SNAPSHOT_LIMIT=30

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

is_safe_relative_glob() {
    local path=${1-} normalized
    normalized=${path//\*/x}
    normalized=${normalized//\?/x}
    is_safe_relative_path "$normalized"
}

require_non_root() {
    if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
        error 'do not run noctalia-mod as root'
        return 1
    fi
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
