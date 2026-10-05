# Dependency discovery and argv construction stay separate so plan output and
# tests never need to invoke a package manager.

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
