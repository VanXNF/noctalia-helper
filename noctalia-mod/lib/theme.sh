# shellcheck shell=bash
# GTK 深浅同步（PLAN §10 P1-8）。
#
# 这件事 Noctalia 不做：它跟着模式设置 `color-scheme`，但**不设** `gtk-theme`，也不写
# `~/.config/gtk-{3,4}.0/settings.ini`——而 Brave/Chromium 冷启动就是靠
# `gtk-application-prefer-dark-theme` 判深浅的（这个坑记在 configs/noctalia/README.md）。
# 旧引擎由 `theme` 命令负责，新项目把它收在这里。
#
# 与旧引擎的差别（有意）：不做 flock 防抖。旧引擎防的是"hook 与 CLI 同时触发"，而新项目
# 现在只在部署收尾调一次；等阶段 G 二进制上了 PATH、真的接 hook 时再谈。模式解析保留，
# 因为部署时没有别的办法知道当前是深还是浅。

# 当前模式：dark / light。顺序与旧引擎一致——Noctalia IPC → gsettings → 默认 dark。
theme_current_mode() {
    local value=''
    if command -v noctalia >/dev/null 2>&1; then
        value=$(timeout 3 noctalia msg theme-mode-get 2>/dev/null) || value=''
        case $value in
            dark | light)
                printf '%s\n' "$value"
                return 0
                ;;
        esac
    fi
    if command -v gsettings >/dev/null 2>&1; then
        value=$(timeout 5 gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null) || value=''
        if [[ -n $value ]]; then
            case $value in
                *prefer-light* | *default*) printf 'light\n' ;;
                *) printf 'dark\n' ;;
            esac
            return 0
        fi
    fi
    printf '%s\n' "${DEFAULT_MODE:-dark}"
}

theme_gtk_name() {
    if [[ $1 == dark ]]; then
        printf '%s\n' "${GTK_THEME_DARK:-adw-gtk3-dark}"
    else
        printf '%s\n' "${GTK_THEME_LIGHT:-adw-gtk3}"
    fi
}

# 往 settings.ini 的 [Settings] 节写两个键，其余内容与顺序原样保留。
# 用临时文件 + mv 落盘：半个 INI 会让 GTK 应用读到坏值。
theme_write_ini() {
    local path=$1 key=$2 value=$3 directory temp line written=0 in_section=0
    directory=$(dirname "$path")
    mkdir -p "$directory" || return 1
    temp=$(mktemp "$directory/.${path##*/}.new.XXXXXX") || return 1
    if [[ -f $path ]]; then
        while IFS= read -r line || [[ -n $line ]]; do
            if [[ $line == '[Settings]' ]]; then
                in_section=1
                printf '%s\n' "$line" >> "$temp"
                printf '%s = %s\n' "$key" "$value" >> "$temp"
                written=1
                continue
            fi
            if ((in_section)) && [[ $line == \[*\] ]]; then
                in_section=0
            fi
            if ((in_section)) && [[ $line == "$key"[' =']* ]]; then
                continue
            fi
            printf '%s\n' "$line" >> "$temp"
        done < "$path"
    fi
    if ((written == 0)); then
        [[ -s $temp ]] && printf '\n' >> "$temp"
        printf '[Settings]\n%s = %s\n' "$key" "$value" >> "$temp"
    fi
    mv -f -- "$temp" "$path"
}

# 把当前模式同步到 gsettings 与两个 settings.ini。失败只警告，不往上抛：
# 这是配置铺好之后的收尾润色，不该把一次成功的部署弄成失败。
theme_sync() {
    local mode gtk scheme version failures=0
    mode=$(theme_current_mode)
    # 与旧引擎一致：认不出来的值一律当深色。
    [[ $mode == light ]] || mode=dark
    gtk=$(theme_gtk_name "$mode")
    if [[ $mode == dark ]]; then
        scheme=prefer-dark
    else
        scheme=prefer-light
    fi
    if command -v gsettings >/dev/null 2>&1; then
        timeout 5 gsettings set org.gnome.desktop.interface color-scheme "$scheme" 2>/dev/null || failures=$((failures + 1))
        timeout 5 gsettings set org.gnome.desktop.interface gtk-theme "$gtk" 2>/dev/null || failures=$((failures + 1))
    else
        warn 'gsettings is unavailable; GTK theme will not follow the current mode'
    fi
    for version in gtk-3.0 gtk-4.0; do
        theme_write_ini "$(config_root)/$version/settings.ini" 'gtk-application-prefer-dark-theme' \
            "$([[ $mode == dark ]] && printf true || printf false)" || failures=$((failures + 1))
        theme_write_ini "$(config_root)/$version/settings.ini" 'gtk-theme-name' "$gtk" || failures=$((failures + 1))
    done
    ((failures)) && warn "theme sync finished with $failures failure(s)"
    printf 'theme\t%s\t%s\t%s\n' "$mode" "$scheme" "$gtk"
    return 0
}

# 只报告，不改动。给 `theme status` 与 doctor 用。
theme_status() {
    local mode scheme current_gtk
    mode=$(theme_current_mode)
    scheme='unknown'
    current_gtk='unknown'
    if command -v gsettings >/dev/null 2>&1; then
        scheme=$(timeout 5 gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null) || scheme='unknown'
        current_gtk=$(timeout 5 gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null) || current_gtk='unknown'
        scheme=${scheme//\'/}
        current_gtk=${current_gtk//\'/}
    fi
    printf 'mode\t%s\n' "$mode"
    printf 'color-scheme\t%s\n' "$scheme"
    printf 'gtk-theme\t%s\n' "$current_gtk"
    printf 'expected-gtk-theme\t%s\n' "$(theme_gtk_name "$mode")"
}

# ── GTK 渲染一侧的收尾（PLAN §11 阶段 F 的 gtktheme）──────────────────────────
#
# 旧引擎里 `gtktheme` 是个独立模块，实际只做三件事：注册模板、催 Noctalia 渲染、
# 清掉旧版留下的 gtk-dark.css 软链。注册本来就随 noctalia 模块的配置发布（gtk3/gtk4
# 两节），剩下两件是引擎级的 GTK 步骤，和写 settings.ini 属同一类，所以收在这里，
# 不为两个命令再建一个模块——那正是这个项目已经砍掉两次的"空转概念"（PLAN §11 阶段 D）。

# 旧版留下的 gtk-dark.css 软链 import 了 libadwaita.css，会盖掉 Material You 颜色。
# 只删软链：用户自己写的同名文件不是我们的东西。
theme_clean_legacy_overrides() {
    local version css
    for version in gtk-3.0 gtk-4.0; do
        css="$(config_root)/$version/gtk-dark.css"
        [[ -L $css ]] || continue
        rm -f -- "$css" || return 1
        printf 'gtk-dark.css\tremoved\t%s\n' "$css"
    done
    return 0
}

# 催 Noctalia 按当前壁纸渲染全部模板。催不动只警告：下一次主题或壁纸变化它还会渲染，
# 而配置本身已经铺好了，不该为此把一次成功的部署弄成失败。
theme_trigger_render() {
    command -v noctalia >/dev/null 2>&1 || return 0
    timeout 15 noctalia msg config-reload >/dev/null 2>&1 || true
    timeout 30 noctalia msg templates-apply >/dev/null 2>&1 ||
        warn 'Noctalia did not render the templates; it will on the next theme change'
    return 0
}
