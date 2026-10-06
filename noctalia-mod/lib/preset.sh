# shellcheck shell=bash
# 用户预设（PLAN §4）：把当前 ~/.config/<模块> 里自己攒出来的样子存成一份可复用的
# 版本，落在 ~/.config/noctalia-mod/presets/<模块>/<名字>/。
#
# 分层顺序：默认配置 → 官方预设（仓库内，只读）→ 用户预设 → __custom__。
# 同名时官方优先——官方预设是随仓库发布的契约，本地同名目录顶不掉它，`save` 也会
# 直接拒绝占用官方名字，免得造出一个永远不生效的目录。
#
# 调用这些函数前必须已经 module_load 过该模块：MODULE_TARGET / MODULE_FILES 是
# 模块协议变量，本文件只读不设。

# `default` 是保留字：它就是"默认配置"，不是一个能存的名字（与 module-loader 的
# MODULE_PRESET_DEFAULT 同一个词）。
preset_is_reserved() {
    [[ ${1-} == default ]]
}

# 这个名字在哪个来源里：official / user / none。
preset_source_of() {
    local module=$1 name=$2 root dir
    root=$(module_root "$module")
    if [[ -d $root/presets/$name && ! -L $root/presets/$name ]]; then
        printf 'official\n'
        return 0
    fi
    dir=$(preset_user_dir "$module" "$name") || {
        printf 'none\n'
        return 0
    }
    if [[ -d $dir && ! -L $dir ]]; then
        printf 'user\n'
        return 0
    fi
    printf 'none\n'
}

# 这次部署会怎么处理这个模块：ok / frozen / reset。
#   ok     —— 账本里的 preset 能解析到，正常部署
#   frozen —— preset 没了而目标还在：保持原样，绝不静默改回默认（旧引擎语义）
#   reset  —— preset 没了且目标也没了：没有东西可丢，回退 default 重铺
# 预检（plan / setup）和 module_deploy 都问这一个函数，判定只有一处。
preset_deploy_mode() {
    local module=$1 preset target
    preset=$(module_state_get "$module" preset 2>/dev/null || true)
    [[ -n $preset ]] || {
        printf 'ok\n'
        return 0
    }
    module_source_for_preset "$(module_root "$module")" "$preset" >/dev/null && {
        printf 'ok\n'
        return 0
    }
    target=$(safe_target_path "$MODULE_TARGET") || {
        printf 'ok\n'
        return 0
    }
    if [[ -e $target || -L $target ]]; then
        printf 'frozen\n'
    else
        printf 'reset\n'
    fi
}

# 可用的 preset 清单：<名字>\t<official|user>\t<yes|no>（yes = 当前活跃）。
# default 永远第一行；用户目录顶着官方名字时不单列——它不会生效，列出来只会让人
# 以为有两份。
preset_catalog() {
    local module=$1 active official_dir user_dir name
    active=$(module_state_get "$module" preset 2>/dev/null || true)
    [[ -n $active ]] || active=default
    printf 'default\tofficial\t%s\n' "$(preset_active_marker "$active" default)"
    official_dir="$(module_root "$module")/presets"
    if [[ -d $official_dir ]]; then
        while IFS= read -r name; do
            printf '%s\tofficial\t%s\n' "$name" "$(preset_active_marker "$active" "$name")"
        done < <(find "$official_dir" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | LC_ALL=C sort)
    fi
    user_dir="$(preset_root)/$module"
    if [[ -d $user_dir && ! -L $user_dir ]]; then
        while IFS= read -r name; do
            is_safe_identifier "$name" || continue
            [[ -d $official_dir/$name ]] && continue
            printf '%s\tuser\t%s\n' "$name" "$(preset_active_marker "$active" "$name")"
        done < <(find "$user_dir" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | LC_ALL=C sort)
    fi
}

preset_active_marker() {
    [[ $1 == "$2" ]] && printf 'yes' || printf 'no'
}

# 把当前部署目标存成用户预设。__custom__ 不进预设：那是用户自己的实时覆盖，
# 每次部署都会被重新继承回来，存进去只会让人误以为它进了"版本"。
preset_save() {
    local module=$1 name=$2 target dest parent staged
    dest=$(preset_user_dir "$module" "$name") || return 1
    target=$(safe_target_path "$MODULE_TARGET") || return 1
    [[ -e $target || -L $target ]] || {
        error "nothing to save: $target does not exist"
        return 1
    }
    [[ $(preset_source_of "$module" "$name") != official ]] || {
        error "preset $name of $module is shipped by the repository; pick another name"
        return 1
    }
    parent=$(dirname "$dest")
    mkdir -p "$parent" || return 1
    staged=$(mktemp -d "$parent/.${name}.noctalia-mod.new.XXXXXX") || return 1
    if [[ -f $target || -L $target ]]; then
        cp -a -- "$target" "$staged/${MODULE_TARGET##*/}" || { rm -rf -- "$staged"; return 1; }
    else
        cp -a -- "$target"/. "$staged"/ || { rm -rf -- "$staged"; return 1; }
        find "$staged" -name '*__custom__*' -exec rm -rf -- {} + || { rm -rf -- "$staged"; return 1; }
    fi
    atomic_swap_staged "$staged" "$dest" || {
        rm -rf -- "$staged"
        error "could not install the preset at $dest"
        return 1
    }
    return 0
}

preset_delete() {
    local module=$1 name=$2 dir
    [[ $(preset_source_of "$module" "$name") != official ]] || {
        error "preset $name of $module is shipped by the repository; it cannot be deleted"
        return 1
    }
    dir=$(preset_user_dir "$module" "$name") || return 1
    [[ -d $dir && ! -L $dir ]] || {
        error "no user preset named $name for module $module"
        return 1
    }
    rm -rf -- "$dir" || return 1
    # 空掉的 <模块>/ 目录一并收掉，不留空壳。
    rmdir "$(dirname "$dir")" 2>/dev/null || true
    return 0
}

# 用 $EDITOR 打开用户预设（非交互时给出路径，不猜用户想干什么）。
preset_edit() {
    local module=$1 name=$2 dir editor
    [[ $(preset_source_of "$module" "$name") != official ]] || {
        error "preset $name of $module is shipped by the repository; edit it there, not in place"
        return 1
    }
    dir=$(preset_user_dir "$module" "$name") || return 1
    [[ -d $dir && ! -L $dir ]] || {
        error "no user preset named $name for module $module"
        return 1
    }
    [[ -t 0 ]] || {
        error "preset edit needs a terminal; the files are under $dir"
        return 1
    }
    editor=${EDITOR:-${VISUAL:-nano}}
    local -a editor_argv=()
    read -r -a editor_argv <<< "$editor"
    ((${#editor_argv[@]})) || {
        error 'EDITOR is empty'
        return 1
    }
    command -v "${editor_argv[0]}" >/dev/null 2>&1 || {
        error "editor not found: ${editor_argv[0]}"
        return 1
    }
    "${editor_argv[@]}" "$dir"
}
