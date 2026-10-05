# Snapshots hold only selected module targets. This keeps the new ledger fully
# separate from Noctalia Mod and makes failed transactions reversible as a unit.

snapshot_root() {
    printf '%s/snapshots\n' "$(state_root)"
}

snapshot_id_new() {
    local id
    while :; do
        id=$(printf 'snapshot_%s_%06d' "$(date -u +%Y%m%d_%H%M%S)" "$RANDOM")
        is_safe_snapshot_id "$id" || return 1
        [[ ! -e $(snapshot_root)/$id ]] && { printf '%s\n' "$id"; return 0; }
    done
}

snapshot_exists() {
    local id=${1-}
    is_safe_snapshot_id "$id" || return 1
    [[ -d $(snapshot_root)/$id ]]
}

snapshot_create() {
    local kind=$1 note=$2
    [[ $note != *$'\t'* && $note != *$'\n'* && $note != *$'\r'* ]] || {
        error 'snapshot notes may not contain tabs or newlines'
        return 1
    }
    shift 2
    local id root manifest module target target_relative copy_path
    id=$(snapshot_id_new)
    root="$(snapshot_root)/$id"
    manifest="$root/modules.tsv"
    mkdir -p "$root/config"
    printf 'created_at\t%s\nkind\t%s\nnote\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$kind" "$note" > "$root/meta.tsv"
    : > "$manifest"
    for module in "$@"; do
        module_load "$module" || { rm -rf -- "$root"; return 1; }
        target=$(safe_target_path "$MODULE_TARGET") || { rm -rf -- "$root"; return 1; }
        target_relative=$MODULE_TARGET
        if [[ -e $target || -L $target ]]; then
            copy_path="$root/config/$target_relative"
            mkdir -p "$(dirname "$copy_path")"
            cp -a -- "$target" "$copy_path" || { rm -rf -- "$root"; return 1; }
            printf '%s\t%s\t1\n' "$module" "$target_relative" >> "$manifest"
        else
            printf '%s\t%s\t0\n' "$module" "$target_relative" >> "$manifest"
        fi
    done
    snapshot_prune "$id"
    printf '%s\n' "$id"
}

snapshot_list() {
    local path id created kind note
    shopt -s nullglob
    for path in "$(snapshot_root)"/snapshot_*; do
        [[ -d $path ]] || continue
        id=${path##*/}
        is_safe_snapshot_id "$id" || continue
        created=$(awk -F '\t' '$1 == "created_at" {print $2}' "$path/meta.tsv" 2>/dev/null || true)
        kind=$(awk -F '\t' '$1 == "kind" {print $2}' "$path/meta.tsv" 2>/dev/null || true)
        note=$(awk -F '\t' '$1 == "note" {print $2}' "$path/meta.tsv" 2>/dev/null || true)
        printf '%s\t%s\t%s\t%s\n' "$id" "$created" "$kind" "$note"
    done | sort -r
    shopt -u nullglob
}

snapshot_latest() {
    snapshot_list | awk -F '\t' 'NR == 1 {print $1}'
}

snapshot_prune() {
    local protected=$1 path count=0 id ignored
    while IFS=$'\t' read -r id ignored; do
        count=$((count + 1))
        if ((count <= NOCTALIA_MOD_SNAPSHOT_LIMIT)); then
            continue
        fi
        [[ $id == "$protected" ]] && continue
        rm -rf -- "$(snapshot_root)/$id"
    done < <(snapshot_list)
    return 0
}

snapshot_delete() {
    local id=${1-}
    is_safe_snapshot_id "$id" || {
        error "invalid snapshot id: $id"
        return 1
    }
    snapshot_exists "$id" || {
        error "snapshot not found: $id"
        return 1
    }
    rm -rf -- "$(snapshot_root)/$id"
}

snapshot_restore() {
    local id=${1-} preserve_custom=${2-}
    is_safe_snapshot_id "$id" || {
        error "invalid snapshot id: $id"
        return 1
    }
    shift 2
    local root line module relative existed target source wanted=0
    root="$(snapshot_root)/$id"
    [[ -f $root/modules.tsv ]] || {
        error "snapshot not found: $id"
        return 1
    }
    while IFS=$'\t' read -r module relative existed; do
        if (($#)); then
            wanted=0
            contains_word "$module" "$@" && wanted=1
            ((wanted)) || continue
        fi
        is_safe_identifier "$module" && is_safe_relative_path "$relative" &&
            [[ $existed == 0 || $existed == 1 ]] || {
            error "snapshot $id contains an unsafe target"
            return 1
        }
        module_load "$module" || return 1
        [[ $relative == "$MODULE_TARGET" ]] || {
            error "snapshot $id target no longer matches module $module"
            return 1
        }
        target=$(safe_target_path "$relative") || return 1
        if [[ $existed == 1 ]]; then
            source="$root/config/$relative"
            [[ -e $source || -L $source ]] || {
                error "snapshot $id is incomplete for $module"
                return 1
            }
            atomic_replace_item "$source" "$target" "$preserve_custom" || return 1
        else
            rm -rf -- "$target"
        fi
    done < "$root/modules.tsv"
    return 0
}

snapshot_for_module() {
    module_state_get "$1" last_snapshot 2>/dev/null || true
}
