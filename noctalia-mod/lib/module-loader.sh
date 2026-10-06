# shellcheck shell=bash
# Module metadata is Bash deliberately: it keeps the new runtime dependency-free
# and only lives in this repository, never in user-writable configuration paths.

MODULE_ID=''
MODULE_TARGET=''
MODULE_FILES='files'
# 模块形状（PLAN §11 阶段 F）：config = 一棵树部署进配置根；system = 自带动作脚本的
# 系统级模块，没有目标树。两者共用包清单、程序声明与账本，差别只在部署那一步。
MODULE_KIND='config'
MODULE_REPO_PACKAGES=()
MODULE_AUR_PACKAGES=()
MODULE_PRESERVE=()
MODULE_RUNTIME_WRITES=()
MODULE_CHMOD=()
MODULE_RELOAD_COMMAND=()
MODULE_VALIDATE_PATHS=()
MODULE_EXTERNAL_REFS=()
MODULE_REQUIRED_COMMANDS=()
MODULE_OPTIONAL_COMMANDS=()
MODULE_EXTERNAL_COMMANDS=()
MODULE_PARTS=()
MODULE_PRESET_DEFAULT='default'
# 系统级模块专属声明（见 lib/system.sh）：预检清单、要 enable 的单元、额外动作，
# 以及"这个动作需要 root 吗"——需要就统一在动手前取一次权限。
MODULE_SYSTEM_PATHS=()
MODULE_SYSTEM_SERVICES=()
MODULE_SYSTEM_EXTRA_ACTIONS=()
MODULE_SYSTEM_PRIVILEGED='no'

# 这些变量是模块协议的一部分：本文件只声明与重置，读取方在 deploy.sh / bin 里。
# 单文件静态分析看不到那些读取点，所以这里关掉 SC2034。
# shellcheck disable=SC2034
module_reset() {
    MODULE_ID=''
    MODULE_TARGET=''
    MODULE_FILES='files'
    MODULE_KIND='config'
    MODULE_REPO_PACKAGES=()
    MODULE_AUR_PACKAGES=()
    MODULE_PRESERVE=()
    MODULE_RUNTIME_WRITES=()
    MODULE_CHMOD=()
    MODULE_RELOAD_COMMAND=()
    MODULE_VALIDATE_PATHS=()
    MODULE_EXTERNAL_REFS=()
    MODULE_REQUIRED_COMMANDS=()
    MODULE_OPTIONAL_COMMANDS=()
    MODULE_EXTERNAL_COMMANDS=()
    MODULE_PARTS=()
    MODULE_PRESET_DEFAULT='default'
    MODULE_SYSTEM_PATHS=()
    MODULE_SYSTEM_SERVICES=()
    MODULE_SYSTEM_EXTRA_ACTIONS=()
    MODULE_SYSTEM_PRIVILEGED='no'
}

# 系统级模块的校验：不许有目标树，必须三件套齐备，声明的路径必须是安全的绝对路径。
module_validate_system() {
    local requested=$1 root=$2 action service path
    [[ -z $MODULE_TARGET ]] || {
        error "system module $requested must not declare a target"
        return 1
    }
    ((${#MODULE_PARTS[@]} == 0)) || {
        error "system module $requested must not declare parts"
        return 1
    }
    for action in install status uninstall "${MODULE_SYSTEM_EXTRA_ACTIONS[@]}"; do
        is_safe_identifier "$action" || {
            error "invalid action in module $requested: $action"
            return 1
        }
        [[ -f $root/actions/$action.sh ]] || {
            error "system module $requested has no actions/$action.sh"
            return 1
        }
    done
    for path in "${MODULE_SYSTEM_PATHS[@]}" "${MODULE_VALIDATE_PATHS[@]}"; do
        is_safe_absolute_path "$path" || {
            error "invalid absolute path in module $requested: $path"
            return 1
        }
    done
    for service in "${MODULE_SYSTEM_SERVICES[@]}"; do
        # systemd 单元名里有 `@` `.` `-`，所以用包名那套字符集，只收形状不收语义。
        is_safe_package_name "$service" || {
            error "invalid systemd unit in module $requested: $service"
            return 1
        }
    done
    case $MODULE_SYSTEM_PRIVILEGED in
        yes | no) ;;
        *)
            error "invalid MODULE_SYSTEM_PRIVILEGED in module $requested: $MODULE_SYSTEM_PRIVILEGED"
            return 1
            ;;
    esac
    return 0
}

module_load() {
    local requested=$1 root conf package path part variable command_entry
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
    case $MODULE_KIND in
        config)
            is_safe_relative_path "$MODULE_TARGET" || {
                error "invalid target in module $requested"
                return 1
            }
            is_safe_relative_path "$MODULE_FILES" && [[ -d $root/$MODULE_FILES ]] || {
                error "module $requested has no valid files directory"
                return 1
            }
            for path in "${MODULE_PRESERVE[@]}" "${MODULE_RUNTIME_WRITES[@]}" "${MODULE_VALIDATE_PATHS[@]}" "${MODULE_EXTERNAL_REFS[@]}"; do
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
                if [[ -z ${!variable:-} ]] || ! is_safe_relative_path "${!variable}"; then
                    error "part $part in module $requested has no valid target"
                    return 1
                fi
                [[ -d $root/parts/$part ]] || {
                    error "part $part in module $requested has no source directory"
                    return 1
                }
            done
            ;;
        system)
            # 目标树专属的声明在系统级模块里没有落点，留着只会让人以为它们生效了。
            for variable in MODULE_PRESERVE MODULE_RUNTIME_WRITES MODULE_CHMOD MODULE_EXTERNAL_REFS; do
                [[ -z ${!variable:-} ]] || {
                    error "$variable is meaningless in system module $requested"
                    return 1
                }
            done
            module_validate_system "$requested" "$root" || return 1
            ;;
        *)
            error "unknown module kind in $requested: $MODULE_KIND"
            return 1
            ;;
    esac
    for package in "${MODULE_REPO_PACKAGES[@]}" "${MODULE_AUR_PACKAGES[@]}"; do
        is_safe_package_name "$package" || {
            error "invalid package in module $requested: $package"
            return 1
        }
    done
    # 必需程序必须写成 命令:包 —— 没有包就没法装，那样的声明没有意义。
    for command_entry in "${MODULE_REQUIRED_COMMANDS[@]}"; do
        if [[ $command_entry != *:* ]] ||
            ! is_safe_command_name "${command_entry%%:*}" ||
            ! is_safe_package_name "${command_entry#*:}"; then
            error "invalid required command in module $requested: $command_entry (expect command:package)"
            return 1
        fi
    done
    for command_entry in "${MODULE_OPTIONAL_COMMANDS[@]}"; do
        [[ $command_entry == *:* ]] && command_entry=${command_entry%%:*}
        is_safe_command_name "$command_entry" || {
            error "invalid optional command in module $requested: $command_entry"
            return 1
        }
    done
    for command_entry in "${MODULE_EXTERNAL_COMMANDS[@]}"; do
        is_safe_command_name "$command_entry" || {
            error "invalid external command in module $requested: $command_entry"
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

# 非 default 的 preset 解析顺序（PLAN §4）：官方在前，用户在后。同名时官方胜出，
# 因为官方预设是随仓库发布的契约；`preset save` 也会拒绝占用官方的名字。
module_source_for_preset() {
    local root=$1 preset=$2 source dir
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
    # 预设目录本身不接受软链：否则"预设"就能变成指向仓库外任意路径的跳板。
    for dir in "$root/presets/$preset" "$(preset_user_dir "$MODULE_ID" "$preset")"; do
        [[ -d $dir && ! -L $dir ]] || continue
        source="$dir/$MODULE_TARGET"
        if [[ -f $source || -L $source ]]; then
            printf '%s\n' "$source"
        else
            printf '%s\n' "$dir"
        fi
        return 0
    done
    return 1
}

module_source_for_part() {
    local root=$1 part=$2 selected=$3 candidate
    is_safe_identifier "$part" && is_safe_identifier "$selected" || return 1
    candidate="$root/parts/$part/$selected"
    [[ -f $candidate ]] || candidate="$root/parts/$part/$selected.kdl"
    [[ -f $candidate ]] || return 1
    printf '%s\n' "$candidate"
}
