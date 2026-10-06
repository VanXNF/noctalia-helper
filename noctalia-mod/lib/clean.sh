# shellcheck shell=bash
# 缓存清理（PLAN §11 阶段 E）。
#
# 这个项目没有自己的缓存目录：部署用的暂存树就建在目标旁边（原子替换要求同一文件
# 系统），完成后就地删掉；`$XDG_CACHE_HOME/noctalia-mod/` 是 Noctalia 渲染 Material You
# 色板的输出位置，不是我们的临时目录（PLAN §4）。所以 `clean` 清的只有一样东西：
# **部署中断留下的暂存树**。它顺带能显式做一次快照清理。
#
# 不碰系统级缓存（pacman 包缓存、journal、TRIM、孤立包）。那些要 root、属于操作系统
# 维护，不属于"配置管理器"；把它们塞进来只会让这条命令变成一个需要提权的万金油。
# 本项目删的东西只有一条判据：路径必须完全落在配置根内，且名字精确匹配我们自己起过的
# 暂存命名。

# 名字形如 .<目标名>.noctalia-mod.<阶段>.<mktemp 后缀>，四个阶段见 deploy.sh。
clean_is_staging_name() {
    local base=${1##*/}
    [[ $base =~ ^\..+\.noctalia-mod\.(new|old|build|uninstall)\.[A-Za-z0-9]{6,}$ ]]
}

clean_staging_paths() {
    local root path
    root=$(config_root)
    [[ -d $root ]] || return 0
    while IFS= read -r -d '' path; do
        # 软链一律不碰：`rm -rf` 对软链本身是安全的，但"跟着软链走"的写法到处都是，
        # 这里干脆不给自己留机会（旧引擎 clean 同款原则）。
        [[ -L $path ]] && continue
        clean_is_staging_name "$path" || continue
        printf '%s\n' "$path"
    done < <(find "$root" -depth -name '*noctalia-mod.*' -print0 2>/dev/null)
    return 0
}

clean_remove_staging() {
    local root path removed=0
    root=$(config_root)
    while IFS= read -r path; do
        [[ -n $path ]] || continue
        # 再核一遍：删除路径只从"配置根之内 + 我们的命名"两重校验里取。
        case $path in
            "$root"/*) ;;
            *)
                warn "refusing a staging path outside the configuration root: $path"
                continue
                ;;
        esac
        clean_is_staging_name "$path" || continue
        rm -rf -- "$path" || return 1
        printf 'staging\tremoved\t%s\n' "$path"
        removed=$((removed + 1))
    done < <(clean_staging_paths)
    [[ $removed -gt 0 ]] || printf 'staging\tnothing to remove\n'
    return 0
}

clean_run() {
    local dry_run=no prune_snapshots=no arg id
    local -a staging=() snapshots=()
    while (($#)); do
        arg=$1
        shift
        case $arg in
            -n | --dry-run) dry_run=yes ;;
            --snapshots) prune_snapshots=yes ;;
            *) error "unknown clean option: $arg"; return 2 ;;
        esac
    done
    printf 'Noctalia Mod clean\n'
    mapfile -t staging < <(clean_staging_paths)
    if [[ $dry_run == yes ]]; then
        for arg in "${staging[@]}"; do
            printf 'staging\twould remove\t%s\n' "$arg"
        done
        ((${#staging[@]})) || printf 'staging\tnothing to remove\n'
    else
        clean_remove_staging || return 1
    fi
    if [[ $prune_snapshots == yes ]]; then
        mapfile -t snapshots < <(snapshot_prune_candidates)
        for id in "${snapshots[@]}"; do
            printf 'snapshot\t%s\t%s\n' "$([[ $dry_run == yes ]] && printf 'would remove' || printf 'removed')" "$id"
        done
        ((${#snapshots[@]})) || printf 'snapshot\tnothing to remove\n'
        if [[ $dry_run == no && ${#snapshots[@]} -gt 0 ]]; then
            snapshot_prune
        fi
    fi
    printf 'summary\t%s staging, %s snapshots\t%s\n' \
        "${#staging[@]}" "${#snapshots[@]}" \
        "$([[ $dry_run == yes ]] && printf 'dry run: nothing was deleted' || printf 'done')"
    return 0
}
