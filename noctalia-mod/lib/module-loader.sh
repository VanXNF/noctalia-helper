# Module metadata is Bash deliberately: it keeps the new runtime dependency-free
# and only lives in this repository, never in user-writable configuration paths.

MODULE_ID=''
MODULE_TARGET=''
MODULE_FILES='files'
MODULE_REPO_PACKAGES=()
MODULE_AUR_PACKAGES=()
MODULE_PRESERVE=()
MODULE_CHMOD=()
MODULE_RELOAD_COMMAND=()
MODULE_VALIDATE_PATHS=()
MODULE_PARTS=()
MODULE_PRESET_DEFAULT='default'

module_reset() {
    MODULE_ID=''
    MODULE_TARGET=''
    MODULE_FILES='files'
    MODULE_REPO_PACKAGES=()
    MODULE_AUR_PACKAGES=()
    MODULE_PRESERVE=()
    MODULE_CHMOD=()
    MODULE_RELOAD_COMMAND=()
    MODULE_VALIDATE_PATHS=()
    MODULE_PARTS=()
    MODULE_PRESET_DEFAULT='default'
}

module_load() {
    local requested=$1 root conf package path part variable
    is_safe_identifier "$requested" || {
        error "invalid module id: $requested"
        return 1
    }
    root=$(module_root "$requested")
    conf="$root/module.conf"
    [[ -f $conf ]] || {
        error "unknown module: $requested"
        return 1
    }
    module_reset
    # shellcheck disable=SC1090
    source "$conf"
    [[ $MODULE_ID == "$requested" ]] || {
        error "module id mismatch in $conf"
        return 1
    }
    is_safe_relative_path "$MODULE_TARGET" || {
        error "invalid target in module $requested"
        return 1
    }
    is_safe_relative_path "$MODULE_FILES" && [[ -d $root/$MODULE_FILES ]] || {
        error "module $requested has no valid files directory"
        return 1
    }
    for package in "${MODULE_REPO_PACKAGES[@]}" "${MODULE_AUR_PACKAGES[@]}"; do
        is_safe_package_name "$package" || {
            error "invalid package in module $requested: $package"
            return 1
        }
    done
    for path in "${MODULE_PRESERVE[@]}" "${MODULE_VALIDATE_PATHS[@]}"; do
        is_safe_relative_path "$path" || {
            error "invalid relative path in module $requested: $path"
            return 1
        }
    done
    for path in "${MODULE_CHMOD[@]}"; do
        is_safe_relative_glob "$path" || {
            error "invalid chmod pattern in module $requested: $path"
            return 1
        }
    done
    for part in "${MODULE_PARTS[@]}"; do
        is_safe_identifier "$part" || {
            error "invalid part in module $requested: $part"
            return 1
        }
        variable="MODULE_PART_${part^^}_TARGET"
        [[ -n ${!variable:-} ]] && is_safe_relative_path "${!variable}" || {
            error "part $part in module $requested has no valid target"
            return 1
        }
        [[ -d $root/parts/$part ]] || {
            error "part $part in module $requested has no source directory"
            return 1
        }
    done
}

module_ids() {
    local path id
    shopt -s nullglob
    for path in "$(project_root)"/modules/*; do
        [[ -d $path && -f $path/module.conf ]] || continue
        id=${path##*/}
        is_safe_identifier "$id" && printf '%s\n' "$id"
    done
    shopt -u nullglob
}

module_part_target() {
    local part=$1 variable="MODULE_PART_${1^^}_TARGET"
    printf '%s\n' "${!variable}"
}

module_part_default() {
    local part=$1 variable="MODULE_PART_${1^^}_DEFAULT"
    printf '%s\n' "${!variable:-default}"
}

module_source_for_preset() {
    local root=$1 preset=$2 source
    if [[ $preset == default ]]; then
        source="$root/$MODULE_FILES/$MODULE_TARGET"
        if [[ -f $source || -L $source ]]; then
            printf '%s\n' "$source"
        else
            printf '%s/%s\n' "$root" "$MODULE_FILES"
        fi
        return
    fi
    is_safe_identifier "$preset" || return 1
    [[ -d $root/presets/$preset ]] || return 1
    source="$root/presets/$preset/$MODULE_TARGET"
    if [[ -f $source || -L $source ]]; then
        printf '%s\n' "$source"
    else
        printf '%s/presets/%s\n' "$root" "$preset"
    fi
}

module_source_for_part() {
    local root=$1 part=$2 selected=$3 candidate
    is_safe_identifier "$part" && is_safe_identifier "$selected" || return 1
    candidate="$root/parts/$part/$selected"
    [[ -f $candidate ]] || candidate="$root/parts/$part/$selected.kdl"
    [[ -f $candidate ]] || return 1
    printf '%s\n' "$candidate"
}
