# shellcheck shell=bash
# Deployment transaction: stage the final tree first, then atomically exchange it.

copy_item_preserving_links() {
    local source=$1 destination=$2
    mkdir -p "$(dirname "$destination")"
    rm -rf -- "$destination"
    cp -a -- "$source" "$destination"
}

copy_custom_entries() {
    local old=$1 staged=$2 item relative
    [[ -d $old ]] || return 0
    while IFS= read -r -d '' item; do
        relative=${item#"$old"/}
        [[ $relative != "$item" ]] || continue
        copy_item_preserving_links "$item" "$staged/$relative"
    done < <(find "$old" -depth -name '*__custom__*' -print0)
}

copy_preserved_entries() {
    local old=$1 staged=$2 relative
    shift 2
    [[ -d $old ]] || return 0
    for relative in "$@"; do
        is_safe_relative_path "$relative" || return 1
        [[ -e $old/$relative || -L $old/$relative ]] || continue
        copy_item_preserving_links "$old/$relative" "$staged/$relative"
    done
}

atomic_swap_staged() {
    local staged=$1 destination=$2 parent base old=''
    parent=$(dirname "$destination")
    base=${destination##*/}
    mkdir -p "$parent"
    if [[ -e $destination || -L $destination ]]; then
        old=$(mktemp -d "$parent/.${base}.noctalia-mod.old.XXXXXX") || return 1
        rmdir "$old"
        if ! mv -- "$destination" "$old"; then
            rm -rf -- "$staged"
            return 1
        fi
    fi
    if ! mv -- "$staged" "$destination"; then
        [[ -n $old && -e $old ]] && mv -- "$old" "$destination" || true
        return 1
    fi
    if [[ -n $old ]]; then
        rm -rf -- "$old"
    fi
}

atomic_replace_item() {
    local source=$1 destination=$2 preserve_custom=$3
    shift 3
    local parent base staged
    parent=$(dirname "$destination")
    base=${destination##*/}
    mkdir -p "$parent"

    if [[ -f $source || -L $source ]]; then
        staged=$(mktemp "$parent/.${base}.noctalia-mod.new.XXXXXX") || return 1
        cp -a -- "$source" "$staged" || { rm -f -- "$staged"; return 1; }
        atomic_swap_staged "$staged" "$destination"
        return
    fi

    [[ -d $source ]] || {
        error "deployment source does not exist: $source"
        return 1
    }
    staged=$(mktemp -d "$parent/.${base}.noctalia-mod.new.XXXXXX") || return 1
    cp -a -- "$source"/. "$staged"/ || { rm -rf -- "$staged"; return 1; }
    if [[ $preserve_custom == yes ]]; then
        copy_custom_entries "$destination" "$staged" || { rm -rf -- "$staged"; return 1; }
    fi
    copy_preserved_entries "$destination" "$staged" "$@" || { rm -rf -- "$staged"; return 1; }
    atomic_swap_staged "$staged" "$destination"
}

replace_home_placeholders() {
    local root=$1 file escaped_home
    escaped_home=$(printf '%s' "$HOME" | sed 's/[&|]/\\&/g')
    while IFS= read -r -d '' file; do
        grep -qF '/home/user' "$file" || continue
        sed -i "s|/home/user|$escaped_home|g" "$file"
    done < <(find "$root" -type f -print0)
}

apply_chmod_rules() {
    local target=$1 pattern path
    shopt -s nullglob
    for pattern in "${MODULE_CHMOD[@]}"; do
        for path in "$target"/$pattern; do
            chmod u+x -- "$path"
        done
    done
    shopt -u nullglob
}

apply_parts_to_stage() {
    local root=$1 staged=$2 id=$3 part selected part_source part_target
    for part in "${MODULE_PARTS[@]}"; do
        selected=$(module_state_get "$id" "part.$part" 2>/dev/null || true)
        [[ -n $selected ]] || selected=$(module_part_default "$part")
        part_source=$(module_source_for_part "$root" "$part" "$selected") || {
            error "module $id has no $part part named $selected"
            return 1
        }
        part_target=$(module_part_target "$part")
        copy_item_preserving_links "$part_source" "$staged/$part_target"
    done
}

build_module_stage() {
    local id=$1 root=$2 preset=$3 destination=$4 source parent base staged
    source=$(module_source_for_preset "$root" "$preset") || {
        error "module $id has no preset named $preset"
        return 1
    }
    parent=$(dirname "$destination")
    base=${destination##*/}
    mkdir -p "$parent"
    if [[ -f $source || -L $source ]]; then
        printf '%s\n' "$source"
        return 0
    fi
    staged=$(mktemp -d "$parent/.${base}.noctalia-mod.build.XXXXXX") || return 1
    cp -a -- "$root/$MODULE_FILES"/. "$staged"/ || { rm -rf -- "$staged"; return 1; }
    if [[ $preset != default ]]; then
        cp -a -- "$source"/. "$staged"/ || { rm -rf -- "$staged"; return 1; }
    fi
    apply_parts_to_stage "$root" "$staged" "$id" || { rm -rf -- "$staged"; return 1; }
    replace_home_placeholders "$staged"
    printf '%s\n' "$staged"
}

module_validate_deployment() {
    local target=$1 relative
    for relative in "${MODULE_VALIDATE_PATHS[@]}"; do
        [[ -e $target/$relative || -L $target/$relative ]] || {
            error "module $MODULE_ID did not produce $relative"
            return 1
        }
    done
}

# 部署指纹（PLAN §1）：只覆盖"本项目会覆盖的文件"，即排除 __custom__ 与
# MODULE_PRESERVE。用户改 __custom__ 是设计内行为，不算漂移；运行时被改写的
# 文件必须声明为 preserve，否则报漂移就是对的——它说明模块元数据漏了一个
# 运行时写入者。权限位不进指纹：apply_chmod_rules 每次部署都会重新施加。
module_fingerprint_stream() {
    local target=$1 path relative preserve skip
    [[ -e $target || -L $target ]] || return 0
    if [[ -L $target ]]; then
        printf 'link\0%s\0' "$(readlink "$target")"
        return 0
    fi
    if [[ -f $target ]]; then
        printf 'file\0'
        sha256sum < "$target" | cut -d' ' -f1
        printf '\0'
        return 0
    fi
    while IFS= read -r -d '' path; do
        relative=${path#"$target"/}
        case $relative in
            *__custom__*) continue ;;
        esac
        skip=''
        for preserve in "${MODULE_PRESERVE[@]}"; do
            [[ $relative == "$preserve" ]] && {
                skip=yes
                break
            }
        done
        [[ -n $skip ]] && continue
        printf '%s\0' "$relative"
        if [[ -L $path ]]; then
            printf 'link\0%s\0' "$(readlink "$path")"
        else
            sha256sum < "$path" | cut -d' ' -f1
            printf '\0'
        fi
    done < <(find "$target" \( -type f -o -type l \) -print0 | LC_ALL=C sort -z)
}

module_fingerprint() {
    local target=$1
    module_fingerprint_stream "$target" | sha256sum | cut -d' ' -f1
}

module_reload() {
    ((${#MODULE_RELOAD_COMMAND[@]})) || return 0
    if ! command -v "${MODULE_RELOAD_COMMAND[0]}" >/dev/null 2>&1; then
        warn "reload skipped for $MODULE_ID: ${MODULE_RELOAD_COMMAND[0]} is unavailable"
        return 0
    fi
    "${MODULE_RELOAD_COMMAND[@]}"
}

module_deploy() {
    local id=$1 part_slot=${2-} root target preset source_or_stage staged='' part_target=''
    local -a preserve_paths=()
    module_load "$id" || return 1
    root=$(module_root "$id")
    target=$(safe_target_path "$MODULE_TARGET") || return 1
    if [[ -n $part_slot ]]; then
        contains_word "$part_slot" "${MODULE_PARTS[@]}" || {
            error "unknown part slot: $part_slot"
            return 1
        }
        part_target=$(module_part_target "$part_slot")
    fi
    local preserve
    for preserve in "${MODULE_PRESERVE[@]}"; do
        [[ $preserve == "$part_target" ]] && continue
        preserve_paths+=("$preserve")
    done
    preset=$(module_state_get "$id" preset 2>/dev/null || true)
    [[ -n $preset ]] || preset=$MODULE_PRESET_DEFAULT
    source_or_stage=$(build_module_stage "$id" "$root" "$preset" "$target") || return 1

    if [[ -f $source_or_stage || -L $source_or_stage ]]; then
        atomic_replace_item "$source_or_stage" "$target" yes "${preserve_paths[@]}" || return 1
    else
        staged=$source_or_stage
        copy_custom_entries "$target" "$staged" || { rm -rf -- "$staged"; return 1; }
        copy_preserved_entries "$target" "$staged" "${preserve_paths[@]}" || { rm -rf -- "$staged"; return 1; }
        atomic_swap_staged "$staged" "$target" || return 1
    fi
    apply_chmod_rules "$target" || return 1
    module_validate_deployment "$target" || return 1
    module_reload || return 1
}

module_clear_managed_config() {
    local id=$1 root target parent base staged
    module_load "$id" || return 1
    root=$(module_root "$id")
    target=$(safe_target_path "$MODULE_TARGET") || return 1
    [[ -e $target || -L $target ]] || return 0
    if [[ -f $target || -L $target ]]; then
        rm -f -- "$target"
        return 0
    fi
    parent=$(dirname "$target")
    base=${target##*/}
    staged=$(mktemp -d "$parent/.${base}.noctalia-mod.uninstall.XXXXXX") || return 1
    copy_custom_entries "$target" "$staged" || { rm -rf -- "$staged"; return 1; }
    copy_preserved_entries "$target" "$staged" "${MODULE_PRESERVE[@]}" || { rm -rf -- "$staged"; return 1; }
    if [[ -z $(find "$staged" -mindepth 1 -print -quit) ]]; then
        rm -rf -- "$staged" "$target"
    else
        atomic_swap_staged "$staged" "$target"
    fi
}
