# shellcheck shell=bash
# Dependency discovery and argv construction stay separate so plan output and
# tests never need to invoke a package manager.

# 由调用方（CLI 的 collect_packages）填充；这里给默认值，便于单独 source 测试。
PLAN_REPO_PACKAGES=()
PLAN_AUR_PACKAGES=()
# install_dependencies 实际装下去的东西，供调用方写账本（PLAN §10 P1-2）。
PLAN_INSTALLED_REPO=()
PLAN_INSTALLED_AUR=()

package_is_installed() {
    command -v pacman >/dev/null 2>&1 && pacman -Q -- "$1" >/dev/null 2>&1
}

package_missing() {
    local package
    for package in "$@"; do
        package_is_installed "$package" || printf '%s\n' "$package"
    done
}

package_aur_helper() {
    local helper
    for helper in paru yay; do
        command -v "$helper" >/dev/null 2>&1 && {
            printf '%s\n' "$helper"
            return 0
        }
    done
    return 1
}

package_install_argv() {
    local source=$1 automatic=$2
    shift 2
    local helper
    if [[ $source == repo ]]; then
        printf '%s\0' sudo pacman -S --needed
        [[ $automatic == yes ]] && printf '%s\0' --noconfirm
        printf '%s\0' -- "$@"
        return
    fi
    helper=$(package_aur_helper) || {
        error 'AUR packages are missing, but neither paru nor yay is available'
        return 1
    }
    printf '%s\0' "$helper" -S --needed
    [[ $automatic == yes ]] && printf '%s\0' --noconfirm
    printf '%s\0' -- "$@"
}

package_install() {
    local source=$1 automatic=$2
    shift 2
    (($#)) || return 0
    if [[ $source == aur ]] && ! package_aur_helper >/dev/null; then
        error 'AUR packages are missing, but neither paru nor yay is available'
        return 1
    fi
    local -a argv=()
    mapfile -d '' -t argv < <(package_install_argv "$source" "$automatic" "$@") || return 1
    "${argv[@]}"
}

# 以下是依赖阶段本身：先确认 AUR helper，再一次性取 sudo 权限，最后分批安装。
# 顺序是有意的——repo 包装到一半才发现没有 AUR helper 是最糟的收场。
require_aur_helper_if_needed() {
    ((${#PLAN_AUR_PACKAGES[@]})) || return 0
    local -a missing_aur=()
    mapfile -t missing_aur < <(package_missing "${PLAN_AUR_PACKAGES[@]}")
    ((${#missing_aur[@]})) || return 0
    package_aur_helper >/dev/null && return 0
    error 'AUR packages are missing, but neither paru nor yay is available'
    return 1
}

# 前置一次性取权限，之后的安装循环不再打断（AGENTS §6）。
preflight_sudo() {
    command -v sudo >/dev/null 2>&1 || {
        error 'sudo is required to install packages'
        return 1
    }
    sudo -v || {
        error 'sudo authentication failed'
        return 1
    }
}

# PLAN_INSTALLED_REPO / PLAN_INSTALLED_AUR 由本函数填、由 CLI 读取写账本；
# 单文件静态分析看不到那个读取点。
# shellcheck disable=SC2034
install_dependencies() {
    local -a missing_repo=() missing_aur=()
    mapfile -t missing_repo < <(package_missing "${PLAN_REPO_PACKAGES[@]}")
    mapfile -t missing_aur < <(package_missing "${PLAN_AUR_PACKAGES[@]}")
    PLAN_INSTALLED_REPO=()
    PLAN_INSTALLED_AUR=()
    ((${#missing_repo[@]} || ${#missing_aur[@]})) || return 0
    require_aur_helper_if_needed || return 1
    preflight_sudo || return 1
    if ((${#missing_repo[@]})); then
        package_install repo yes "${missing_repo[@]}" || return 1
        PLAN_INSTALLED_REPO=("${missing_repo[@]}")
    fi
    if ((${#missing_aur[@]})); then
        package_install aur yes "${missing_aur[@]}" || return 1
        PLAN_INSTALLED_AUR=("${missing_aur[@]}")
    fi
    return 0
}

# 程序层核对（PLAN §10 P1-6）：包装完了不等于命令就在 PATH 上——包名对不上、
# 二进制改名、PATH 没刷新都会出现"deps 报齐全但快捷键是坏的"。
# 只报选定模块：`deps niri` 不该去说 fish 的二进制在不在——那不是用户这次问的事，
# 而 niri 自己 spawn 的东西（kitty、wpctl…）本来就在 niri 的声明里（PLAN §3）。
# 输出 <module>\t<程序>\t<包>\t<required|optional>。
runtime_command_report() {
    local id entry command package
    for id in "$@"; do
        module_load "$id" || continue
        for entry in "${MODULE_REQUIRED_COMMANDS[@]}"; do
            command=${entry%%:*}
            package=$(command_entry_package "$entry" || true)
            command -v "$command" >/dev/null 2>&1 && continue
            printf '%s\t%s\t%s\trequired\n' "$id" "$command" "$package"
        done
        for entry in "${MODULE_OPTIONAL_COMMANDS[@]}"; do
            command=${entry%%:*}
            package=$(command_entry_package "$entry" || true)
            command -v "$command" >/dev/null 2>&1 && continue
            printf '%s\t%s\t%s\toptional\n' "$id" "$command" "$package"
        done
    done | sort -u
}

# 可选程序目录：<模块>\t<程序>\t<包>\t<installed|missing>。`setup --with` 认的就是
# 这里的程序名——命令行不能绕过"谁 spawn 谁声明"的契约（PLAN §3）。
# 没绑包的声明装不了，包列写 `-`，预检里照常提示，只是加装不了。
package_optional_catalog() {
    local id entry command package state
    for id in "$@"; do
        module_load "$id" || continue
        for entry in "${MODULE_OPTIONAL_COMMANDS[@]}"; do
            command=${entry%%:*}
            package=$(command_entry_package "$entry" || printf -- '-')
            if command -v "$command" >/dev/null 2>&1; then
                state=installed
            else
                state=missing
            fi
            printf '%s\t%s\t%s\t%s\n' "$id" "$command" "$package" "$state"
        done
    done
}

# 可选程序的包该从哪个来源装。协议里可选程序只写 `命令:包`、不带来源，所以按包名
# 回查模块声明：出现在 AUR 清单里就是 AUR，否则走官方仓库。
package_source_for() {
    local wanted=$1
    shift
    local id
    for id in "$@"; do
        module_load "$id" || continue
        contains_word "$wanted" "${MODULE_AUR_PACKAGES[@]}" && {
            printf 'aur\n'
            return 0
        }
    done
    printf 'repo\n'
}
