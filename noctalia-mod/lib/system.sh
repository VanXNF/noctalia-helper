# shellcheck shell=bash
# 系统级可选模块（PLAN §11 阶段 F）。
#
# 配置模块的模型是"一棵树换一棵树"：目标在配置根内、先暂存再原子替换、失败整棵回滚。
# 系统级模块没有这个形状——它们要写 /etc、enable systemd 单元、用 fish 装插件、把素材
# 放进 ~/.local/share。硬塞进"目标目录"只会得到一个假装原子的东西，所以它们换一套契约：
# 模块自带动作脚本，引擎负责预检、调用、记账。
#
#   modules/<id>/actions/install.sh    装：把这件事做完
#   modules/<id>/actions/status.sh     查：只读探测，健康退 0、不健康非 0
#   modules/<id>/actions/uninstall.sh  卸：还原
#   额外动作由 MODULE_SYSTEM_EXTRA_ACTIONS 声明（如 fcitx5 的 activate）
#
# 动作脚本是独立进程：它自己 source lib/*.sh，用的是同一套原语。引擎不替它做原子替换，
# 也不替它回滚——系统级动作没法"换回去"，备份与还原是动作自己的责任（旧引擎也是这么分的）。
#
# 包由引擎装，不由动作装：模块照旧声明 MODULE_REPO_PACKAGES / MODULE_AUR_PACKAGES，
# `deps`/`install`/`setup` 走同一条安装通道。动作只做系统配置，缺了包就报错退出。
#
# 预检清单是声明出来的（MODULE_SYSTEM_PATHS / MODULE_SYSTEM_SERVICES），不是从脚本里
# 猜出来的：这份清单必须诚实，它决定用户看到的那一次确认值不值。

module_is_system() {
    [[ ${MODULE_KIND:-config} == system ]]
}

system_module_action_script() {
    local id=$1 action=$2
    is_safe_identifier "$action" || return 1
    printf '%s/actions/%s.sh\n' "$(module_root "$id")" "$action"
}

# 引擎侧入口：跑一个动作脚本。环境变量是它唯一需要的输入，其余靠自己 source lib。
system_module_run_action() {
    local id=$1 action=$2 script
    module_load "$id" || return 1
    module_is_system || {
        error "module $id is not a system module"
        return 1
    }
    script=$(system_module_action_script "$id" "$action") || return 1
    [[ -f $script ]] || {
        error "module $id has no $action action"
        return 1
    }
    NOCTALIA_MOD_ID=$id NOCTALIA_MOD_ACTION=$action bash -- "$script"
}

# 装完之后必须存在的绝对路径。动作脚本自己负责把事做完做对，这里只钉住"结果在不在"。
system_module_validate_paths() {
    local path
    for path in "${MODULE_VALIDATE_PATHS[@]}"; do
        [[ -e $path || -L $path ]] || {
            error "module $MODULE_ID did not produce $path"
            return 1
        }
    done
}

system_module_install() {
    local id=$1
    system_module_run_action "$id" install || {
        error "module $id: install action failed"
        return 1
    }
    system_module_validate_paths || return 1
    module_reload || return 1
    return 0
}

system_module_uninstall() {
    local id=$1
    system_module_run_action "$id" uninstall || {
        error "module $id: uninstall action failed"
        return 1
    }
}

# doctor 用：只读探测，输出丢掉，只看退出码。
system_module_is_healthy() {
    local id=$1
    system_module_run_action "$id" status >/dev/null 2>&1
}

# 选定的系统模块里有没有需要 root 的：有就统一次取权限，别让动作跑到一半才弹 sudo
# （PLAN §0 的"权限一次性取"）。
system_modules_need_privileges() {
    local id
    for id in "$@"; do
        module_load "$id" || continue
        [[ ${MODULE_SYSTEM_PRIVILEGED:-no} == yes ]] && return 0
    done
    return 1
}

# ── 动作脚本用的原语 ─────────────────────────────────────────────────────────
#
# 写系统文件不经过 shell：内容先进私有临时文件，再由 `sudo install` 按 root:root 装到位。
# 这样文件内容永远不会被当成命令行的一部分（旧引擎的 greeter 同样这么做）。

# 读系统文件要能不问密码：`status` / `doctor` 是只读探测，不该因为一个 sudo 提示卡住
# （也不该为了读一个自己写的记录文件去提权）。所以这里用 `sudo -n`——没有缓存凭证就
# 直接失败，由调用方当作"读不到"。写路径不受影响：那些是特权动作，引擎已经先取过权限。
system_read_root_file() {
    local path=$1
    if [[ -r $path ]]; then
        cat -- "$path"
        return
    fi
    command -v sudo >/dev/null 2>&1 || return 1
    sudo -n cat -- "$path"
}

system_write_root_file() {
    local source=$1 destination=$2 mode=${3:-644} temp
    command -v sudo >/dev/null 2>&1 || {
        error 'sudo is required to write system files'
        return 1
    }
    temp=$(mktemp) || return 1
    if ! cp -- "$source" "$temp"; then
        rm -f -- "$temp"
        return 1
    fi
    sudo install -D -o root -g root -m "$mode" -- "$temp" "$destination"
    local rc=$?
    rm -f -- "$temp"
    return "$rc"
}

system_write_root_text() {
    local content=$1 destination=$2 mode=${3:-644} temp
    temp=$(mktemp) || return 1
    printf '%s' "$content" > "$temp" || {
        rm -f -- "$temp"
        return 1
    }
    system_write_root_file "$temp" "$destination" "$mode"
    local rc=$?
    rm -f -- "$temp"
    return "$rc"
}

# 备份只做一次：`cp -n` 保证反复 install 不会把"原始版本"覆盖成"我们上次写的版本"。
system_backup_root_file() {
    local path=$1 backup="$1.noctalia-mod.bak"
    command -v sudo >/dev/null 2>&1 || return 1
    [[ -e $path || -L $path ]] || return 0
    [[ -e $backup || -L $backup ]] && return 0
    sudo cp -n -- "$path" "$backup"
}

system_restore_root_file() {
    local path=$1 backup="$1.noctalia-mod.bak"
    command -v sudo >/dev/null 2>&1 || return 1
    [[ -e $backup || -L $backup ]] || return 1
    sudo mv -f -- "$backup" "$path"
}

system_clear_root_file() {
    local path=$1
    command -v sudo >/dev/null 2>&1 || return 1
    sudo rm -f -- "$path"
}

system_unit_enabled() {
    command -v systemctl >/dev/null 2>&1 || return 1
    systemctl is-enabled -- "$1" >/dev/null 2>&1
}

system_unit_enable() {
    local unit=$1 force=${2-no}
    command -v sudo >/dev/null 2>&1 || return 1
    # --force 用于抢回 display-manager.service 这类别名：不带它，systemctl 会拒绝
    # 覆盖一个已经被别人（比如 greetd）拿走的别名。
    if [[ $force == yes ]]; then
        sudo systemctl enable --force "$unit" || return 1
    else
        sudo systemctl enable "$unit" || return 1
    fi
    system_unit_enabled "$unit"
}

system_unit_disable() {
    command -v sudo >/dev/null 2>&1 || return 1
    sudo systemctl disable "$1" || return 1
    system_unit_enabled "$1" && return 1
    return 0
}

# 系统文件里会写进一个可执行路径（greetd 的 session 命令），由 root 执行。所以那个
# 路径必须落在只读的系统目录里、由 root 拥有，且每一级祖先都不可被组/其他写——
# 否则用户目录里放个同名文件就能让 root 跑它（旧引擎的 _trusted_executable 同款检查）。
system_dir_is_root_locked() {
    local dir=$1 owner mode rest
    owner=$(stat -c '%u' -- "$dir" 2>/dev/null) || return 1
    mode=$(stat -c '%a' -- "$dir" 2>/dev/null) || return 1
    [[ $owner == 0 ]] || return 1
    rest=${mode: -2}
    [[ ${rest:0:1} != [2367] && ${rest:1:1} != [2367] ]]
}

system_trusted_executable() {
    local candidate=${1-} path dir owner
    [[ -n $candidate ]] || return 1
    # 控制字符与 shell 元字符一律不收：这个字符串会进 root 拥有的配置文件。
    case $candidate in
        *[!A-Za-z0-9/._+-]* | *..*) return 1 ;;
    esac
    path=$(readlink -f -- "$candidate" 2>/dev/null) || return 1
    [[ -f $path && -x $path ]] || return 1
    case $path in
        /usr/bin/* | /usr/local/bin/*) ;;
        *) return 1 ;;
    esac
    owner=$(stat -c '%u' -- "$path" 2>/dev/null) || return 1
    [[ $owner == 0 ]] || return 1
    dir=$(dirname -- "$path")
    while :; do
        system_dir_is_root_locked "$dir" || return 1
        [[ $dir == / ]] && break
        dir=$(dirname -- "$dir")
    done
    printf '%s\n' "$path"
}

# ── INI 就地编辑 ─────────────────────────────────────────────────────────────
#
# fcitx5 的 classicui.conf 是用户的文件：注释、键序、别的节都要原样留着，我们只动
# 自己那两个键（Theme / DarkTheme）。旧版 fcitx5 写的是"没有节头的平铺键"，那种
# 形状也得认——否则我们会追加一个没人读的 [ClassicUI]，而真正生效的旧键还留着旧值。

ini_file_has_sections() {
    grep -qE '^[[:space:]]*\[' "${1-}" 2>/dev/null
}

ini_get_section_key() {
    local file=$1 section=$2 key=$3 line trimmed in_section=0
    [[ -f $file ]] || return 1
    ini_file_has_sections "$file" || in_section=1
    while IFS= read -r line || [[ -n $line ]]; do
        trimmed=${line#"${line%%[![:space:]]*}"}
        if [[ $trimmed == \[*\] ]]; then
            in_section=0
            [[ $trimmed == "[$section]" ]] && in_section=1
            continue
        fi
        ((in_section)) || continue
        [[ $trimmed == "$key"=* ]] || continue
        printf '%s\n' "${trimmed#*=}"
        return 0
    done < "$file"
    return 1
}

ini_set_section_key() {
    local file=$1 section=$2 key=$3 value=$4
    local line trimmed in_section=0 written=0 flat=no temp directory
    directory=$(dirname "$file")
    mkdir -p "$directory" || return 1
    temp=$(mktemp "$directory/.${file##*/}.new.XXXXXX") || return 1
    if [[ -f $file ]]; then
        if ini_file_has_sections "$file"; then
            while IFS= read -r line || [[ -n $line ]]; do
                trimmed=${line#"${line%%[![:space:]]*}"}
                if [[ $trimmed == \[*\] ]]; then
                    in_section=0
                    if [[ $trimmed == "[$section]" ]]; then
                        printf '%s\n%s=%s\n' "$line" "$key" "$value" >> "$temp"
                        in_section=1
                        written=1
                    else
                        printf '%s\n' "$line" >> "$temp"
                    fi
                    continue
                fi
                ((in_section)) && [[ $trimmed == "$key"=* ]] && continue
                printf '%s\n' "$line" >> "$temp"
            done < "$file"
        else
            flat=yes
            while IFS= read -r line || [[ -n $line ]]; do
                trimmed=${line#"${line%%[![:space:]]*}"}
                if [[ $trimmed == "$key"=* ]]; then
                    printf '%s=%s\n' "$key" "$value" >> "$temp"
                    written=1
                    continue
                fi
                printf '%s\n' "$line" >> "$temp"
            done < "$file"
        fi
    fi
    if ((written == 0)); then
        [[ -s $temp ]] && printf '\n' >> "$temp"
        if [[ $flat == yes ]]; then
            printf '%s=%s\n' "$key" "$value" >> "$temp"
        else
            printf '[%s]\n%s=%s\n' "$section" "$key" "$value" >> "$temp"
        fi
    fi
    mv -f -- "$temp" "$file"
}

ini_unset_section_key() {
    local file=$1 section=$2 key=$3 line trimmed in_section=0 temp directory
    [[ -f $file ]] || return 0
    directory=$(dirname "$file")
    temp=$(mktemp "$directory/.${file##*/}.new.XXXXXX") || return 1
    ini_file_has_sections "$file" || in_section=1
    while IFS= read -r line || [[ -n $line ]]; do
        trimmed=${line#"${line%%[![:space:]]*}"}
        if [[ $trimmed == \[*\] ]]; then
            in_section=0
            [[ $trimmed == "[$section]" ]] && in_section=1
            printf '%s\n' "$line" >> "$temp"
            continue
        fi
        ((in_section)) && [[ $trimmed == "$key"=* ]] && continue
        printf '%s\n' "$line" >> "$temp"
    done < "$file"
    mv -f -- "$temp" "$file"
}
