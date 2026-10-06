#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# 卸：撤掉我们放进去的东西，一个字节都不多删。
#
# 只还原"现在还是我们写的那个值"的主题选择——用户后来自己换过主题就不碰。素材与渲染
# 产物只删我们那三个文件名，主题目录里用户自己的文件留着（旧引擎同款）。
#
# 不动 noctalia-config.toml：那份模板注册属于 noctalia 模块，它带 requires_path，
# 皮肤没了自然就跳过（PLAN §11 阶段 F）。也不删 fcitx5/profile 里的 rime 条目——
# 那是用户输入法列表的一部分，删它等于替用户改输入法。
source "$(dirname -- "${BASH_SOURCE[0]}")/_common.sh"

theme_dir="$HOME/.local/share/fcitx5/themes/nyxmellow"
rime_dir="$HOME/.local/share/fcitx5/rime"
classicui="$HOME/.config/fcitx5/conf/classicui.conf"
previous="$(state_root)/fcitx5-nyxmellow-theme.prev"

# 1. 还原 classicui 的 Theme / DarkTheme。
if [[ -f $previous ]]; then
    existed=$(awk -F= '$1 == "Existed" {print $2}' "$previous")
    saved_theme=$(awk -F= '$1 == "Theme" {print $2}' "$previous")
    saved_dark=$(awk -F= '$1 == "DarkTheme" {print $2}' "$previous")
    for key in Theme DarkTheme; do
        case $key in
            Theme) saved=$saved_theme ;;
            DarkTheme) saved=$saved_dark ;;
        esac
        current=$(ini_get_section_key "$classicui" ClassicUI "$key" || true)
        [[ $current == nyxmellow ]] || continue
        if [[ $existed != 1 || -z $saved ]]; then
            # 这个键原来就不存在（或者没有值）：删掉它，别留一个空键。
            ini_unset_section_key "$classicui" ClassicUI "$key" || exit 1
            printf 'classicui\t%s removed (it was not set before)\n' "$key"
        else
            ini_set_section_key "$classicui" ClassicUI "$key" "$saved" || exit 1
            printf 'classicui\t%s restored to %s\n' "$key" "$saved"
        fi
    done
    rm -f -- "$previous"
    # 文件本来不存在，撤完只剩空节头与注释就收掉它：留一个 [ClassicUI] 空壳没有意义。
    if [[ $existed != 1 && -f $classicui ]]; then
        remaining=$(grep -vE '^[[:space:]]*(#|$|\[)' "$classicui" || true)
        if [[ -z $remaining ]]; then
            rm -f -- "$classicui"
            printf 'classicui\tremoved (it did not exist before)\n'
        fi
    fi
fi

# 2. 删我们自己放进去的素材与渲染产物，然后只在目录空了的时候收掉目录。
for name in theme.conf panel.svg highlight.svg; do
    rm -f -- "$theme_dir/$name" "$theme_dir/templates/$name"
done
rmdir -- "$theme_dir/templates" 2>/dev/null || true
rmdir -- "$theme_dir" 2>/dev/null || true
printf 'templates\tremoved\t%s\n' "$theme_dir"

# 3. 撤掉我们加进 rime 的方案选择行。留下的文件只剩骨架（或本来就空）就删掉它，
#    别给用户留一个读不通的空 patch。
custom="$rime_dir/default.custom.yaml"
if [[ -f $custom ]]; then
    kept=$(grep -v 'schema: rime_ice' "$custom" || true)
    if [[ -z ${kept//[[:space:]]/} || ${kept//[[:space:]]/} == 'patch:schema_list:' ]]; then
        rm -f -- "$custom"
        printf 'rime-ice\tremoved\t%s\n' "$custom"
    else
        temp=$(mktemp "$rime_dir/.default.custom.yaml.XXXXXX") || exit 1
        printf '%s\n' "$kept" > "$temp" || exit 1
        mv -f -- "$temp" "$custom" || exit 1
        printf 'rime-ice\tunpatched\t%s\n' "$custom"
    fi
fi

user_yaml="$rime_dir/user.yaml"
if [[ -f $user_yaml ]]; then
    kept=$(grep -v 'previously_selected_schema: rime_ice' "$user_yaml" || true)
    if [[ -z ${kept//[[:space:]]/} ]]; then
        rm -f -- "$user_yaml"
    else
        temp=$(mktemp "$rime_dir/.user.yaml.XXXXXX") || exit 1
        printf '%s\n' "$kept" > "$temp" || exit 1
        mv -f -- "$temp" "$user_yaml" || exit 1
    fi
fi

fcitx_reload
printf 'nc\tprofile\tleft alone: rime stays in %s (remove it in fcitx5-configtool)\n' "$HOME/.config/fcitx5/profile"
exit 0
