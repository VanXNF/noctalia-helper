#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# 设为默认：把 classicui.conf 的 Theme / DarkTheme 指向 NyxMellow，然后让 fcitx5 重载。
#
# 覆盖之前先把用户原来那两个值记进账本（只记一次，反复 activate 不会把"原始值"覆盖成
# 我们自己写的值）；卸载时只有"现在还是我们写的那个"才还原，用户后来自己换过主题就不碰。
source "$(dirname -- "${BASH_SOURCE[0]}")/_common.sh"

classicui="$HOME/.config/fcitx5/conf/classicui.conf"
previous="$(state_root)/fcitx5-nyxmellow-theme.prev"

if [[ ! -f $previous ]]; then
    existed=0
    saved_theme=''
    saved_dark=''
    if [[ -f $classicui ]]; then
        existed=1
        saved_theme=$(ini_get_section_key "$classicui" ClassicUI Theme || true)
        saved_dark=$(ini_get_section_key "$classicui" ClassicUI DarkTheme || true)
    fi
    mkdir -p "$(dirname "$previous")" || exit 1
    printf 'Existed=%s\nTheme=%s\nDarkTheme=%s\n' "$existed" "$saved_theme" "$saved_dark" > "$previous" || exit 1
fi

ini_set_section_key "$classicui" ClassicUI Theme nyxmellow || exit 1
ini_set_section_key "$classicui" ClassicUI DarkTheme nyxmellow || exit 1
printf 'classicui\tTheme=nyxmellow DarkTheme=nyxmellow\t%s\n' "$classicui"
fcitx_reload_classicui
exit 0
