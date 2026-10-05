# shellcheck shell=bash
# 静态引用自洽校验（PLAN §3）。
#
# 模块源里出现的 ~/.config/... 路径，必须在部署之后真实存在：要么由某个已接入
# 模块提供，要么在 module.conf 的 MODULE_EXTERNAL_REFS 里显式登记（运行时会话
# 产物，或本阶段不接管的外部文件）。没有第三条路——悬空引用一律报错。
#
# 只做静态文本提取，不执行配置。支持两种写法：
#   1. 直接写死的配置路径：~/.config/x、$HOME/.config/x、/home/user/.config/x、
#      ${XDG_CONFIG_HOME:-$HOME/.config}/x
#   2. 目录变量再拼文件名：VAR="<配置根>/dir" ... "$VAR/file"
# 其它写法（拼接、循环生成）不在覆盖范围内。

# 把"配置根"的各种写法归一成标记，后续只认这个标记。
# 单引号里的 $ 是有意的：这些模式匹配的是文件里字面写着的 $HOME / ${HOME}，
# 绝不能在这里展开。
# shellcheck disable=SC2016
reference_normalize() {
    sed -E \
        -e 's#\$\{XDG_CONFIG_HOME:-[^}]*\}#@@CFG@@#g' \
        -e 's#\$\{XDG_CONFIG_HOME\}#@@CFG@@#g' \
        -e 's#\$XDG_CONFIG_HOME#@@CFG@@#g' \
        -e 's#\$\{HOME\}/\.config#@@CFG@@#g' \
        -e 's#\$HOME/\.config#@@CFG@@#g' \
        -e 's#/home/user/\.config#@@CFG@@#g' \
        -e 's#~/\.config#@@CFG@@#g'
}

# 单个文件里引用到的配置相对路径。
reference_refs_in_file() {
    local file=$1 normalized pattern var dir name line
    normalized=$(reference_normalize < "$file")

    printf '%s\n' "$normalized" |
        grep -oE '@@CFG@@/[A-Za-z0-9._@+-]+(/[A-Za-z0-9._@+-]+)*' |
        sed 's#^@@CFG@@/##'

    # 目录变量拼接：VAR="@@CFG@@/dir" 之后出现 "$VAR/name" 或 "${VAR}/name"
    while IFS= read -r line; do
        [[ -n $line ]] || continue
        var=${line%%=*}
        dir=${line#*=}
        dir=${dir#\"}
        dir=${dir#@@CFG@@/}
        while IFS= read -r name; do
            printf '%s/%s\n' "$dir" "$name"
        done < <(
            pattern='[$][{]?'"$var"'[}]?/[A-Za-z0-9._@+-]+'
            printf '%s\n' "$normalized" | grep -oE "$pattern" | sed -E 's#^[^/]*/##'
        )
    done < <(
        printf '%s\n' "$normalized" |
            grep -oE '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*="?@@CFG@@/[^"[:space:];]+'
    )
}

# 某个模块源树（files/presets/parts）里的全部引用。
reference_refs_for_module() {
    local id=$1 root=$2 path
    for path in "$root/$MODULE_FILES" "$root/presets" "$root/parts"; do
        [[ -d $path ]] || continue
        while IFS= read -r -d '' file; do
            reference_refs_in_file "$file"
        done < <(find "$path" -type f -not -path '*__pycache__*' -print0)
    done
}

# 已接入模块部署之后会存在哪些配置相对路径。
reference_deployed_paths() {
    local id root target rel part variable path
    while IFS= read -r id; do
        module_load "$id" || continue
        root=$(module_root "$id")
        target=$MODULE_TARGET
        if [[ -f $root/$MODULE_FILES/$target || -L $root/$MODULE_FILES/$target ]]; then
            printf '%s\n' "$target"
        elif [[ -d $root/$MODULE_FILES ]]; then
            while IFS= read -r -d '' path; do
                rel=${path#"$root/$MODULE_FILES"/}
                printf '%s/%s\n' "$target" "$rel"
            done < <(find "$root/$MODULE_FILES" \( -type f -o -type l \) -print0)
        fi
        # 预设稀疏覆盖：每个预设目录里的文件都映射到同一目标下
        if [[ -d $root/presets ]]; then
            while IFS= read -r -d '' path; do
                rel=${path#"$root/presets"/}
                rel=${rel#*/}
                printf '%s/%s\n' "$target" "$rel"
            done < <(find "$root/presets" \( -type f -o -type l \) -print0)
        fi
        # 零件目标文件本身也是部署产物
        for part in "${MODULE_PARTS[@]}"; do
            variable="MODULE_PART_${part^^}_TARGET"
            printf '%s\n' "${!variable}"
        done
    done < <(module_ids)
}

# 引用 ref 是否落在部署集合里：要么就是其中一项，要么是其中某项的祖先目录。
reference_is_covered() {
    local ref=$1 item
    shift
    for item in "$@"; do
        [[ $item == "$ref" ]] && return 0
        [[ $item == "$ref"/* ]] && return 0
    done
    return 1
}

# 输出未解析引用：<module>\t<relative-path>。全部解析成功则不输出任何东西。
reference_check_unresolved() {
    local -a coverage=()
    local id root ref found=0
    mapfile -t coverage < <(reference_deployed_paths | sort -u)
    while IFS= read -r id; do
        module_load "$id" || return 1
        root=$(module_root "$id")
        while IFS= read -r ref; do
            [[ -n $ref ]] || continue
            reference_is_covered "$ref" "${coverage[@]}" && continue
            contains_word "$ref" "${MODULE_EXTERNAL_REFS[@]}" && continue
            printf '%s\t%s\n' "$id" "$ref"
            found=1
        done < <(reference_refs_for_module "$id" "$root" | sort -u)
    done < <(module_ids)
    return "$found"
}

# ── 程序层引用自洽（PLAN §3 / §10 P1-6）────────────────────────────────────────
#
# 配置路径查的是"文件在不在"，这里查的是"程序在不在、声明得对不对"。
# 分两件事：
#   1. 配置里 spawn 的程序必须被声明（必需/可选/基础系统），否则漏装没人发现。
#   2. 必需程序必须写明提供它的包，否则 deps 装不到它。

# KDL 里 spawn / spawn-at-startup 的首个参数就是程序名。注释先剥掉，
# 否则示例行会被当成真的引用。
command_spawn_programs() {
    local root=$1 path line
    for path in "$root/$MODULE_FILES" "$root/presets" "$root/parts"; do
        [[ -d $path ]] || continue
        while IFS= read -r -d '' file; do
            while IFS= read -r line; do
                [[ -n $line ]] || continue
                case $line in
                    /*|'~'*|'$'*|*/*) continue ;;
                esac
                printf '%s\n' "$line"
            done < <(
                sed -E 's#//.*$##' "$file" |
                    grep -oE 'spawn(-at-startup)?[[:space:]]+"[^"]+"' |
                    sed -E 's/.*"([^"]+)"$/\1/'
            )
        done < <(find "$path" -type f -name '*.kdl' -print0)
    done
}

# 模块是否声明过这个程序（必需 / 可选 / 基础系统都算已声明）。
command_is_declared() {
    local wanted=$1 entry
    for entry in "${MODULE_REQUIRED_COMMANDS[@]}" "${MODULE_OPTIONAL_COMMANDS[@]}" "${MODULE_EXTERNAL_COMMANDS[@]}"; do
        [[ ${entry%%:*} == "$wanted" ]] && return 0
    done
    return 1
}

# 必需程序的包是否在该模块的包清单里。声明了却没人装，等于没声明。
command_package_declared() {
    local wanted=$1 package
    command_entry_package "$wanted" >/dev/null || return 1
    package=$(command_entry_package "$wanted")
    contains_word "$package" "${MODULE_REPO_PACKAGES[@]}" && return 0
    contains_word "$package" "${MODULE_AUR_PACKAGES[@]}" && return 0
    return 1
}

# 输出 <module>\t<程序>，以及 <module>\t<程序>:<包> 形式的绑定问题。
command_check_undeclared() {
    local id root program found=0
    while IFS= read -r id; do
        module_load "$id" || return 1
        root=$(module_root "$id")
        while IFS= read -r program; do
            [[ -n $program ]] || continue
            command_is_declared "$program" && continue
            printf '%s\t%s\n' "$id" "$program"
            found=1
        done < <(command_spawn_programs "$root" | sort -u)
    done < <(module_ids)
    return "$found"
}

command_check_unbound() {
    local id entry found=0
    while IFS= read -r id; do
        module_load "$id" || return 1
        for entry in "${MODULE_REQUIRED_COMMANDS[@]}"; do
            command_package_declared "$entry" && continue
            printf '%s\t%s\n' "$id" "$entry"
            found=1
        done
    done < <(module_ids)
    return "$found"
}
