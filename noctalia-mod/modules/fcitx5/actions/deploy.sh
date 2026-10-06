#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# 部署素材：把 NyxMellow 模板放进 fcitx5 的主题目录，并催一次 Noctalia 渲染。
#
# 它**不**改写 classicui.conf —— 当前用哪个主题是用户的，部署素材不等于设成默认。
# 这条分界就是 PLAN §11 阶段 F 说的"部署素材与设为默认解耦"：`action fcitx5 deploy`
# 只铺素材，`action fcitx5 activate`（或 install）才动主题选择。
source "$(dirname -- "${BASH_SOURCE[0]}")/_common.sh"

theme_dir="$HOME/.local/share/fcitx5/themes/nyxmellow"
source_dir="$NOCTALIA_MOD_ROOT/assets/fcitx5/nyxmellow/templates"

[[ -d $source_dir ]] || {
    error "the NyxMellow templates are missing: $source_dir"
    exit 1
}
mkdir -p "$theme_dir" || exit 1
# 素材是"我们的一棵树"：换素材时整棵替换，不是逐个文件覆盖（旧引擎同款）。
atomic_replace_item "$source_dir" "$theme_dir/templates" no || {
    error 'could not deploy the NyxMellow templates'
    exit 1
}
printf 'templates\tdeployed\t%s\n' "$theme_dir/templates"

# 模板注册在 noctalia 模块的配置里（带 requires_path，没装皮肤时那条是惰性的），
# 所以这里只负责催渲染。催不动不算失败：下一次主题或壁纸变化 Noctalia 还会渲染。
if command -v noctalia >/dev/null 2>&1; then
    timeout 15 noctalia msg config-reload >/dev/null 2>&1 || true
    if timeout 30 noctalia msg templates-apply >/dev/null 2>&1; then
        printf 'render\tdone\t%s\n' "$theme_dir"
    else
        printf 'render\tpending\tNoctalia will render on its next theme change\n'
    fi
fi
exit 0
