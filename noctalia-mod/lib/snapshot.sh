# shellcheck shell=bash
# Snapshots hold only selected module targets. This keeps the new ledger fully
# separate from Noctalia Mod and makes failed transactions reversible as a unit.

# 快照保留上限（只算普通快照，受保护快照不占名额）。属于快照自己的概念，
# 不放在 common.sh 里。
NOCTALIA_MOD_SNAPSHOT_LIMIT=30

snapshot_root() {
    printf '%s/snapshots\n' "$(state_root)"
}

# 所有删除路径都从这里取：root 与 id 都过了校验才返回，避免 rm -rf 打到别处。
snapshot_path_for() {
    local id=${1-} root
    is_safe_snapshot_id "$id" || return 1
    root=$(snapshot_root) || return 1
    [[ -n $root && $root == /* ]] || return 1
    printf '%s/%s\n' "$root" "$id"
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
        # 系统级模块没有配置树可存：它的还原点是动作脚本自己留的备份，快照管不到，
        # 硬记一条空目标只会让 snapshot_apply 在恢复时找不到东西（PLAN §11 阶段 F）。
        module_is_system && continue
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
    done | LC_ALL=C sort -t "$(printf '\t')" -k2,2r -k1,1r
    shopt -u nullglob
}

snapshot_latest() {
    snapshot_list | awk -F '\t' 'NR == 1 {print $1}'
}

# 最近一个指定类型的快照（如 pre-restore 的保护快照）。
snapshot_newest_of_kind() {
    local wanted=$1 line
    while IFS= read -r line; do
        [[ $(printf '%s' "$line" | cut -f3) == "$wanted" ]] || continue
        printf '%s' "$line" | cut -f1
        return 0
    done < <(snapshot_list)
    return 1
}

# 清理时绝对不能删的快照：
#   - 调用方指定的（通常是刚建好的那个）
#   - 每个模块账本里的 last_snapshot —— 那是 uninstall 用来恢复用户原配置的东西，
#     删了它，卸载就会在用户不知情的情况下把原文件弄丢
#   - 最近一次恢复保护快照 —— 那是"撤销这次恢复"的唯一退路
#   - SNAPSHOT_PROTECT_EXTRA 里的钉子 —— 正在被恢复的那个快照可能已经排在第 30 名
#     之外，而恢复过程本身会先创建保护快照（也就是会 prune）；不钉住它，就会在应用
#     之前被自己的 prune 吃掉
SNAPSHOT_PROTECT_EXTRA=()

snapshot_protected_ids() {
    local extra=${1-} file value newest pin
    [[ -n $extra ]] && printf '%s\n' "$extra"
    for pin in "${SNAPSHOT_PROTECT_EXTRA[@]}"; do
        [[ -n $pin ]] && printf '%s\n' "$pin"
    done
    shopt -s nullglob
    for file in "$(state_root)"/modules/*.state; do
        value=$(state_get "$file" last_snapshot 2>/dev/null || true)
        [[ -n $value ]] && printf '%s\n' "$value"
    done
    shopt -u nullglob
    newest=$(snapshot_newest_of_kind pre-restore 2>/dev/null || true)
    [[ -n $newest ]] && printf '%s\n' "$newest"
    return 0
}

# 保留 = 全部受保护快照 + 最近的 N 个普通快照；其余是"可以删"的。删与预览问的是
# 同一个清单，所以 `clean -n` 看到的和真删的一模一样。
snapshot_prune_candidates() {
    local extra=${1-} id _ keep=0
    local -a protected=()
    mapfile -t protected < <(snapshot_protected_ids "$extra" | sort -u)
    while IFS=$'\t' read -r id _; do
        [[ -n $id ]] || continue
        contains_word "$id" "${protected[@]}" && continue
        keep=$((keep + 1))
        ((keep <= NOCTALIA_MOD_SNAPSHOT_LIMIT)) && continue
        printf '%s\n' "$id"
    done < <(snapshot_list)
    return 0
}

# 受保护的不占名额：宁可多留几个，也不删掉唯一的恢复点。
snapshot_prune() {
    local extra=${1-} id path
    while IFS= read -r id; do
        [[ -n $id ]] || continue
        path=$(snapshot_path_for "$id") || continue
        rm -rf -- "$path"
    done < <(snapshot_prune_candidates "$extra")
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
    local file value
    shopt -s nullglob
    for file in "$(state_root)"/modules/*.state; do
        value=$(state_get "$file" last_snapshot 2>/dev/null || true)
        [[ $value == "$id" ]] || continue
        warn "snapshot $id is the recovery point for module ${file##*/}; removing it means uninstall cannot restore the original files"
    done
    shopt -u nullglob
    local path
    path=$(snapshot_path_for "$id") || return 1
    rm -rf -- "$path"
}

# 快照里列出的模块，可只取其中几个。恢复事务要先知道自己会动哪些模块，才能在失败时
# 把它们放回去，所以这件事单独问一次。
snapshot_modules() {
    local id=$1 root module relative existed
    shift
    root="$(snapshot_root)/$id"
    [[ -f $root/modules.tsv ]] || return 1
    while IFS=$'\t' read -r module relative existed; do
        [[ -n $module ]] || continue
        if (($#)); then
            contains_word "$module" "$@" || continue
        fi
        printf '%s\n' "$module"
    done < "$root/modules.tsv"
    return 0
}

# 原始恢复：逐模块原子替换，走到哪算哪。这是内部原语，事务包装在 snapshot_restore。
snapshot_apply() {
    local id=${1-} preserve_custom=${2-}
    is_safe_snapshot_id "$id" || {
        error "invalid snapshot id: $id"
        return 1
    }
    shift 2
    local root module relative existed target source wanted=0
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

# 最近一次恢复创建的保护快照 ID，给调用方提示"怎么撤销这次恢复"。
# 读取方在 bin/noctalia-mod（单文件静态分析看不到它的读取点）。
# 注意：snapshot_restore 会写这个变量，所以别把它放在命令替换里调用。
SNAPSHOT_LAST_GUARD=''

# 恢复是一个事务（PLAN §10 P2）：先把这些模块的当前状态存成保护快照，任何一步失败就
# 用它把已经改过的模块放回去。没有这一步，恢复失败的收场是"一半新一半旧"，而账本还
# 指着原来那个快照——下一次操作就会建立在这个说不清的状态上。
# 它同时写 SNAPSHOT_LAST_GUARD，那个变量的读取点在 bin/noctalia-mod。
# shellcheck disable=SC2034
snapshot_restore() {
    local id=${1-} preserve_custom=${2-}
    shift 2
    is_safe_snapshot_id "$id" || {
        error "invalid snapshot id: $id"
        return 1
    }
    snapshot_exists "$id" || {
        error "snapshot not found: $id"
        return 1
    }
    local -a modules=()
    mapfile -t modules < <(snapshot_modules "$id" "$@")
    ((${#modules[@]})) || {
        error "snapshot $id lists no module target to restore"
        return 1
    }
    local guard
    SNAPSHOT_PROTECT_EXTRA=("$id")
    guard=$(snapshot_create pre-restore "before restoring $id" "${modules[@]}") || {
        SNAPSHOT_PROTECT_EXTRA=()
        return 1
    }
    SNAPSHOT_PROTECT_EXTRA=()
    SNAPSHOT_LAST_GUARD=$guard
    if ! snapshot_apply "$id" "$preserve_custom" "${modules[@]}"; then
        error "restoring $id failed; putting the touched modules back the way they were"
        snapshot_apply "$guard" no "${modules[@]}" ||
            error "automatic rollback failed; $guard holds the state from before this restore"
        return 1
    fi
    return 0
}

snapshot_for_module() {
    module_state_get "$1" last_snapshot 2>/dev/null || true
}
