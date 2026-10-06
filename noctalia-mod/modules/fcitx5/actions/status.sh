#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# 查：只读探测。健康（我们自己那部分到位）退 0，缺东西退 1 并列出缺什么。
#
# "渲染产物在不在"只作为信息报出来，不算不健康：那是 Noctalia 的活，还没渲染说明
# 主题还没变过一次，不是这个模块坏了。同理，ime 没在跑也不影响判定。
source "$(dirname -- "${BASH_SOURCE[0]}")/_common.sh"

theme_dir="$HOME/.local/share/fcitx5/themes/nyxmellow"
classicui="$HOME/.config/fcitx5/conf/classicui.conf"
profile="$HOME/.config/fcitx5/profile"
custom="$HOME/.local/share/fcitx5/rime/default.custom.yaml"
failed=0

if [[ -f $theme_dir/templates/theme.conf ]]; then
    printf 'templates\tpresent\t%s\n' "$theme_dir/templates"
else
    printf 'templates\tmissing\t%s\n' "$theme_dir/templates"
    failed=1
fi

if [[ -f $theme_dir/theme.conf && -f $theme_dir/panel.svg && -f $theme_dir/highlight.svg ]]; then
    printf 'rendered\tpresent\t%s\n' "$theme_dir"
else
    printf 'rendered\tpending\tNoctalia renders theme.conf, panel.svg and highlight.svg here\n'
fi

if [[ -f $custom ]] && grep -q 'schema: rime_ice' "$custom"; then
    printf 'rime-ice\tconfigured\t%s\n' "$custom"
else
    printf 'rime-ice\tmissing\t%s\n' "$custom"
    failed=1
fi

if [[ -f $profile ]] && grep -q '^Name=rime$' "$profile"; then
    printf 'profile\trime\tenabled\n'
else
    printf 'profile\trime\tmissing from %s\n' "$profile"
    failed=1
fi

if [[ -f $classicui ]]; then
    theme=$(ini_get_section_key "$classicui" ClassicUI Theme || printf 'unset')
    dark=$(ini_get_section_key "$classicui" ClassicUI DarkTheme || printf 'unset')
    printf 'classicui\tTheme=%s DarkTheme=%s\t%s\n' "$theme" "$dark" "$classicui"
else
    printf 'classicui\tmissing\t%s\n' "$classicui"
fi

if command -v fcitx5 >/dev/null 2>&1; then
    printf 'fcitx5\tinstalled\t%s\n' "$(command -v fcitx5)"
else
    printf 'fcitx5\tnot-on-path\tinstall the declared packages with: noctalia-mod deps fcitx5\n'
fi

exit "$failed"
