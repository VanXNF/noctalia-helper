#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# 雾凇拼音（rime_ice）：挂上方案、能预编译就预编译、把 rime 加进 fcitx5 的输入法列表。
#
# 这一步在旧引擎里是 `.optional-apps.toml` 的 post_install 钩子
# （`post_install = "fcitx:setup_rime_ice"`）。新项目没有这条缝：声明 `rime-ice-git`
# 的模块自己就是那个钩子，"装了包顺带把方案配好"由 `install <模块>` 表达。
#
# 与旧引擎的一处差别：挂载一律由我们写 YAML（确定、可重复），rime_deployer 只用来
# 预编译。旧引擎先试 `rime_deployer --add-schema`，那一步的行为取决于版本。
source "$(dirname -- "${BASH_SOURCE[0]}")/_common.sh"

rime_dir="$HOME/.local/share/fcitx5/rime"
profile="$HOME/.config/fcitx5/profile"
custom="$rime_dir/default.custom.yaml"

ensure_trailing_newline() {
    [[ -s $1 && -n $(tail -c1 -- "$1") ]] && printf '\n' >> "$1"
    return 0
}

mkdir -p "$rime_dir" "$(dirname "$profile")" || exit 1

# 1. 挂上 rime_ice：只加自己那一行，用户原有的 patch 内容原样保留。
if [[ -f $custom ]] && grep -q 'schema: rime_ice' "$custom"; then
    printf 'rime\tschema\talready selected\n'
elif [[ -f $custom ]] && grep -q 'patch:' "$custom"; then
    if grep -q 'schema_list:' "$custom"; then
        temp=$(mktemp "$rime_dir/.default.custom.yaml.XXXXXX") || exit 1
        awk '!done && /schema_list:/ {print; print "    - schema: rime_ice"; done=1; next} {print}' \
            "$custom" > "$temp" || exit 1
        mv -f -- "$temp" "$custom" || exit 1
    else
        ensure_trailing_newline "$custom"
        printf '  schema_list:\n    - schema: rime_ice\n' >> "$custom" || exit 1
    fi
    printf 'rime\tschema\tselected in the existing patch\n'
elif [[ -s $custom ]]; then
    ensure_trailing_newline "$custom"
    printf '\npatch:\n  schema_list:\n    - schema: rime_ice\n' >> "$custom" || exit 1
    printf 'rime\tschema\tpatch appended\n'
else
    printf 'patch:\n  schema_list:\n    - schema: rime_ice\n' > "$custom" || exit 1
    printf 'rime\tschema\tpatch written\t%s\n' "$custom"
fi

# 2. 预编译。没有 rime_deployer 就只写 user.yaml 记住选择——方案要等 fcitx5 首次启动
#    自己编译，功能不残，只是第一次启动慢一点。
#
#    `--set-active-schema` 必须在 rime 目录里跑：它按相对路径写 user.yaml，在别处跑会
#    把文件丢进调用者的 cwd（真踩过，仓库根多了一个 user.yaml）。
if command -v rime_deployer >/dev/null 2>&1 && [[ -d /usr/share/rime-data ]]; then
    timeout 45 rime_deployer --build "$rime_dir" /usr/share/rime-data "$rime_dir/build" >/dev/null 2>&1 || true
    (cd -- "$rime_dir" && timeout 15 rime_deployer --set-active-schema rime_ice >/dev/null 2>&1) || true
    printf 'rime\tprebuilt\t%s/build\n' "$rime_dir"
else
    rime_remember_selection "$rime_dir/user.yaml" || exit 1
    printf 'rime\tprebuild-skipped\trime_deployer is unavailable; fcitx5 will build on first start\n'
fi

# 3. 保证 rime 在 fcitx5 的输入法列表里。空 profile 就写一份可用的默认；已有则在
#    [GroupOrder] 之前插一项，索引往后排（旧引擎同款，保留用户已有的输入法条目）。
if [[ -f $profile ]] && grep -q '^Name=rime$' "$profile"; then
    printf 'rime\tprofile\talready present\n'
elif [[ ! -s $profile ]]; then
    cat > "$profile" <<'PROFILE'
[Groups/0]
Name=默认
Default Layout=us
DefaultIM=keyboard-us

[Groups/0/Items/0]
Name=rime
Layout=

[Groups/0/Items/1]
Name=keyboard-us
Layout=

[GroupOrder]
0=默认
PROFILE
    printf 'rime\tprofile\tdefault profile written\n'
else
    next=0
    while IFS= read -r index; do
        [[ $index =~ ^[0-9]+$ ]] || continue
        ((index >= next)) && next=$((index + 1))
    done < <(grep -oE '^\[Groups/0/Items/[0-9]+\]' "$profile" | grep -oE '[0-9]+')
    addition=$(printf '[Groups/0/Items/%s]\nName=rime\nLayout=\n' "$next")
    if grep -q '^\[GroupOrder\]' "$profile"; then
        temp=$(mktemp "$(dirname "$profile")/.profile.XXXXXX") || exit 1
        awk -v addition="$addition" \
            '/^\[GroupOrder\]/ && !done {printf "%s\n", addition; done=1} {print}' \
            "$profile" > "$temp" || exit 1
        mv -f -- "$temp" "$profile" || exit 1
    else
        ensure_trailing_newline "$profile"
        printf '\n%s' "$addition" >> "$profile" || exit 1
    fi
    printf 'rime\tprofile\tadded as item %s\n' "$next"
fi

fcitx_reload
exit 0
