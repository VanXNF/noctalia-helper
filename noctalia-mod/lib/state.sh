# shellcheck shell=bash
# Small tab-separated ledger. Values are controlled scalar data and are never
# sourced as shell code. Every mutating CLI path is enclosed by with_project_lock.

state_module_file() {
    local id=$1
    is_safe_identifier "$id" || return 1
    printf '%s/modules/%s.state\n' "$(state_root)" "$id"
}

state_get() {
    local file=$1 key=$2
    [[ -f $file ]] || return 1
    awk -F '\t' -v wanted="$key" '$1 == wanted { sub(/^[^\t]*\t/, ""); print; exit }' "$file"
}

# 合并写入：本次没提到的键原样保留，已存在的键就地更新，新键追加到末尾。
# 覆盖式重写会让新增字段被下一次 install 静默抹掉——账本字段只会越来越多，
# 每次写都得把整个 schema 记全是不现实的（PLAN §10 P1-3）。
state_put_many() {
    local file=$1
    shift
    (( $# % 2 == 0 )) || {
        error 'state writes take key/value pairs'
        return 1
    }
    local -a keys=() values=() written=()
    local key value directory temp index old_key old_value matched
    while (($#)); do
        key=$1
        value=$2
        shift 2
        [[ -n $key && $key != *$'\t'* && $key != *$'\n'* && $value != *$'\t'* && $value != *$'\n'* ]] || {
            error 'state keys must be non-empty and free of tabs and newlines'
            return 1
        }
        keys+=("$key")
        values+=("$value")
    done
    directory=$(dirname "$file")
    mkdir -p "$directory"
    temp=$(mktemp "$directory/.${file##*/}.new.XXXXXX") || return 1
    if [[ -f $file ]]; then
        while IFS=$'\t' read -r old_key old_value; do
            matched=''
            for index in "${!keys[@]}"; do
                [[ ${keys[index]} == "$old_key" ]] || continue
                matched=yes
                if [[ -z ${written[index]:-} ]]; then
                    printf '%s\t%s\n' "${keys[index]}" "${values[index]}" >> "$temp"
                    written[index]=1
                fi
                break
            done
            [[ -n $matched ]] && continue
            printf '%s\t%s\n' "$old_key" "$old_value" >> "$temp"
        done < "$file"
    fi
    for index in "${!keys[@]}"; do
        [[ -n ${written[index]:-} ]] && continue
        printf '%s\t%s\n' "${keys[index]}" "${values[index]}" >> "$temp"
    done
    mv -f -- "$temp" "$file"
}

module_state_get() {
    local id=$1 key=$2 file
    file=$(state_module_file "$id") || return 1
    state_get "$file" "$key"
}

module_state_write() {
    local id=$1
    shift
    local file
    file=$(state_module_file "$id") || return 1
    state_put_many "$file" "$@"
}

state_module_set() {
    local id=$1 file
    shift
    file=$(state_module_file "$id") || return 1
    state_put_many "$file" "$@"
}

state_module_unset() {
    local id=$1 key=$2 file temp old_key old_value
    file=$(state_module_file "$id") || return 1
    [[ -f $file ]] || return 0
    temp=$(mktemp "$(dirname "$file")/.${id}.state.new.XXXXXX") || return 1
    while IFS=$'\t' read -r old_key old_value; do
        [[ $old_key == "$key" ]] || printf '%s\t%s\n' "$old_key" "$old_value" >> "$temp"
    done < "$file"
    mv -f -- "$temp" "$file"
}

# 合并写入不再顺手清掉陈旧键，所以"整族键"的清理要显式做（如模块去掉了某个零件插槽）。
state_module_unset_prefix() {
    local id=$1 prefix=$2 file temp old_key old_value
    file=$(state_module_file "$id") || return 1
    [[ -f $file ]] || return 0
    temp=$(mktemp "$(dirname "$file")/.${id}.state.new.XXXXXX") || return 1
    while IFS=$'\t' read -r old_key old_value; do
        [[ $old_key == "$prefix"* ]] || printf '%s\t%s\n' "$old_key" "$old_value" >> "$temp"
    done < "$file"
    mv -f -- "$temp" "$file"
}

module_state_remove() {
    local id=$1 file
    file=$(state_module_file "$id") || return 1
    rm -f -- "$file"
}

state_enabled_modules() {
    local file id
    shopt -s nullglob
    for file in "$(state_root)"/modules/*.state; do
        id=${file##*/}
        id=${id%.state}
        [[ $(state_get "$file" enabled 2>/dev/null || true) == 1 ]] && printf '%s\n' "$id"
    done
    shopt -u nullglob
}

state_append_audit() {
    local event=$1 details=${2-} audit temp
    audit="$(state_root)/audit.log"
    mkdir -p "$(state_root)"
    temp=$(mktemp "$(state_root)/.audit.new.XXXXXX") || return 1
    [[ -f $audit ]] && cat -- "$audit" > "$temp"
    printf '%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$event" "$details" >> "$temp"
    mv -f -- "$temp" "$audit"
}

# 本项目实际装过的包（PLAN §7 / §10 P1-2）。只记"我们装的"，不记本来就在的——
# 否则将来的显式清理会去删用户自己装的东西。时间戳留给 audit.log，这里只回答
# "哪些包是我们装的、从哪个来源"。
state_installed_packages_file() {
    printf '%s/packages.tsv\n' "$(state_root)"
}

state_record_installed_packages() {
    local source=$1
    shift
    (($#)) || return 0
    case $source in
        repo|aur) ;;
        *) error "unknown package source: $source"; return 1 ;;
    esac
    local -a pairs=()
    local package
    for package in "$@"; do
        is_safe_package_name "$package" || continue
        pairs+=("$package" "$source")
    done
    ((${#pairs[@]})) || return 0
    state_put_many "$(state_installed_packages_file)" "${pairs[@]}"
}

# 输出 <包>\t<来源>
state_installed_packages() {
    local file
    file=$(state_installed_packages_file)
    [[ -f $file ]] || return 0
    cat -- "$file"
}

state_project_version() {
    git -C "$(project_root)" rev-parse --short HEAD 2>/dev/null || printf 'unknown\n'
}
