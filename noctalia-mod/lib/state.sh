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

state_put_many() {
    local file=$1
    shift
    local directory temp key value
    directory=$(dirname "$file")
    mkdir -p "$directory"
    temp=$(mktemp "$directory/.${file##*/}.new.XXXXXX") || return 1
    while (($#)); do
        key=$1
        value=$2
        shift 2
        [[ $key != *$'\t'* && $key != *$'\n'* && $value != *$'\t'* && $value != *$'\n'* ]] || {
            rm -f -- "$temp"
            error 'state values may not contain tabs or newlines'
            return 1
        }
        printf '%s\t%s\n' "$key" "$value" >> "$temp"
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
    local id=$1 key=$2 value=$3 file temp old_key old_value
    file=$(state_module_file "$id") || return 1
    [[ $key != *$'\t'* && $key != *$'\n'* && $value != *$'\t'* && $value != *$'\n'* ]] || {
        error 'state values may not contain tabs or newlines'
        return 1
    }
    temp=$(mktemp "$(dirname "$file")/.${id}.state.new.XXXXXX") || return 1
    if [[ -f $file ]]; then
        while IFS=$'\t' read -r old_key old_value; do
            [[ $old_key == "$key" ]] || printf '%s\t%s\n' "$old_key" "$old_value" >> "$temp"
        done < "$file"
    fi
    printf '%s\t%s\n' "$key" "$value" >> "$temp"
    mv -f -- "$temp" "$file"
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

state_project_version() {
    git -C "$(project_root)" rev-parse --short HEAD 2>/dev/null || printf 'unknown\n'
}
