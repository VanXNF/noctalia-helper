# shellcheck shell=bash
# 壁纸部署与 managed 账本（PLAN §11 阶段 D）。
#
# 位置：壁纸是**用户可见的数据**，不在 ~/.config 里，所以它不归任何模块，也没法用模块
# 目标表达（引擎只允许写配置根内的相对路径）。因此这一段是引擎自己的步骤，跟着 `setup`
# 走，另外给一个显式命令。`install` 不碰它——那个命令的契约是"只动 ~/.config"。
#
# 账本：`<壁纸目录>/.noctalia-mod-managed`，一行一个顶层名字——本项目放进去的东西。
# 清理只删账本里的条目，绝不碰用户自己的壁纸。不用 JSON：Bash 里逐行文本既好写又好读，
# 而名字里可能出现引号与非 ASCII，JSON 反而要多一层转义。
#
# 同步一律 no-clobber：同名文件已存在就跳过（用户的版本优先），但仍记进账本——那个位置
# 是我们放的，用户删掉它不该怪我们，我们也不该把它当成自己的。
# 远程壁纸包下载**不迁**：旧引擎也只把它做成显式可选，全新机器不需要几十 MB 的 clone。

# 壁纸目录：与 Noctalia 配置里的 `directory` 同一个基准（PLAN §4 的 @XDG_PICTURES@）。
wallpaper_dir() {
    printf '%s/Wallpapers\n' "$(pictures_dir)"
}

wallpaper_ledger_path() {
    printf '%s/.noctalia-mod-managed\n' "$(wallpaper_dir)"
}

# 离线素材源：仓库自带的 assets/wallpapers/
wallpaper_source_dir() {
    printf '%s/assets/wallpapers\n' "$(project_root)"
}

# 账本里的顶层名字，一行一个。账本不存在就什么都不输出。
wallpaper_managed_entries() {
    local ledger
    ledger=$(wallpaper_ledger_path)
    [[ -f $ledger ]] || return 0
    awk 'NF' "$ledger"
}

# 把顶层名字写成账本；一个都没有就删掉账本，不留空文件。
wallpaper_write_ledger() {
    local destination temp
    destination=$(wallpaper_dir)
    [[ -d $destination ]] || return 0
    temp=$(mktemp "$destination/.noctalia-mod-managed.XXXXXX") || return 1
    if printf '%s\n' "$@" | awk 'NF && !seen[$0]++' > "$temp" && [[ -s $temp ]]; then
        mv -f -- "$temp" "$(wallpaper_ledger_path)"
        return 0
    fi
    rm -f -- "$temp" "$(wallpaper_ledger_path)"
}

# 把离线素材同步进壁纸目录，并把这轮涉及的顶层名字合并进账本。
# 输出 added / skipped 两行，供调用方汇报。
wallpaper_deploy() {
    local source destination entry relative parent added=0 skipped=0
    local -a managed=()
    source=$(wallpaper_source_dir)
    destination=$(wallpaper_dir)
    [[ -d $source ]] || {
        warn "no offline wallpapers to deploy ($source is missing)"
        return 0
    }
    mkdir -p "$destination" || return 1
    while IFS= read -r -d '' entry; do
        relative=${entry#"$source"/}
        [[ $relative != "$entry" ]] || continue
        is_safe_relative_path "$relative" || continue
        if [[ -e $destination/$relative || -L $destination/$relative ]]; then
            skipped=$((skipped + 1))
        else
            parent=$(dirname "$destination/$relative")
            mkdir -p "$parent" || return 1
            cp -a -- "$entry" "$destination/$relative" || return 1
            added=$((added + 1))
        fi
        managed+=("${relative%%/*}")
    done < <(find "$source" \( -type f -o -type l \) -print0 | LC_ALL=C sort -z)
    # 账本记顶层名字（旧引擎同款）：目录型的记目录名，文件型的记文件名。
    mapfile -t -O "${#managed[@]}" managed < <(wallpaper_managed_entries)
    wallpaper_write_ledger "${managed[@]}" || return 1
    printf 'wallpapers\t%s new, %s already present\t%s\n' "$added" "$skipped" "$destination"
    return 0
}

wallpaper_status() {
    local destination ledger count
    destination=$(wallpaper_dir)
    ledger=$(wallpaper_ledger_path)
    printf 'directory\t%s\t%s\n' "$destination" "$([[ -d $destination ]] && printf present || printf missing)"
    count=$(wallpaper_managed_entries | wc -l)
    printf 'managed\t%s\n' "$((count))"
    printf 'ledger\t%s\n' "$([[ -f $ledger ]] && printf present || printf absent)"
}

# 只删账本记录的顶层条目，用户自己的壁纸一个都不碰。名字逐条校验：空、`.`、`..`、含
# 分隔符或换行的条目一律拒绝（那是越出壁纸目录的路径），并且**留在账本里**——拒绝不等于
# 可以遗忘，下次还会再报一次。
wallpaper_remove_managed() {
    local destination entry target removed=0
    local -a refused=()
    destination=$(wallpaper_dir)
    while IFS= read -r entry; do
        [[ -n $entry ]] || continue
        case $entry in
            . | .. | */* | *$'\n'* | *$'\r'*)
                warn "refusing an unsafe ledger entry: $entry"
                refused+=("$entry")
                continue
                ;;
        esac
        target="$destination/$entry"
        [[ -e $target || -L $target ]] || continue
        rm -rf -- "$target" || return 1
        removed=$((removed + 1))
    done < <(wallpaper_managed_entries)
    if ((${#refused[@]})); then
        wallpaper_write_ledger "${refused[@]}"
    else
        rm -f -- "$(wallpaper_ledger_path)"
    fi
    printf 'wallpapers\t%s removed\t%s\n' "$removed" "$destination"
    return 0
}
