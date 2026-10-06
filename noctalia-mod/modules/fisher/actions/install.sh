#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# 装：按固定 commit + sha256 取 fisher 引导脚本，用它装三个钉住的插件，并把这次
# 写进去的文件记进所有权账本。
#
# 三条拒绝规则（旧引擎同款，都是为了"不接管别人的东西"）：
#   1. 部署出来的锁文件不是本模块钉住的那份 → 拒绝（用户改过插件列表，听他的）。
#   2. 已经有 fisher、却没有我们的账本 → 拒绝（那是别人装的，我们不接管）。
#   3. 账本说上次只装到一半 → 继续装，并把这次新增的文件并进账本（可安全重试）。
source "$(dirname -- "${BASH_SOURCE[0]}")/_common.sh"

record=$(fisher_record_path)

command -v fish >/dev/null 2>&1 || {
    error 'fish is not on PATH; run: noctalia-mod deps fisher'
    exit 1
}
fisher_lockfile_matches || {
    error "refusing to install: $FISHER_DIR/fish_plugins is not the plugin list this module pins"
    error 'restore it with: noctalia-mod install fish --yes'
    exit 1
}

if fisher_load_ownership "$record"; then
    if [[ $FISHER_COMPLETE == yes ]]; then
        complete=yes
        for relative in "${FISHER_OWNED_FILES[@]}"; do
            [[ -f $FISHER_DIR/$relative || -L $FISHER_DIR/$relative ]] || complete=no
        done
        if [[ $complete == yes ]]; then
            printf 'fisher\tcurrent\t%s\n' "$FISHER_DIR"
            exit 0
        fi
        printf 'fisher\trepairing\tsome owned files are missing\n'
    else
        printf 'fisher\tresuming\tthe previous run did not finish\n'
    fi
elif [[ -f $FISHER_DIR/functions/fisher.fish || -L $FISHER_DIR/functions/fisher.fish ]]; then
    error "fisher is already installed in $FISHER_DIR without a noctalia-mod ownership record"
    error 'refusing to take it over; remove it yourself first if you want this module to manage it'
    exit 1
else
    FISHER_OWNED_FILES=()
    fisher_write_ownership 0 || exit 1
fi

bootstrap=$(mktemp --suffix=.fish) || exit 1
temp_config=$(mktemp -d) || exit 1
trap 'rm -f -- "$bootstrap"; rm -rf -- "$temp_config"' EXIT

mapfile -t mirrors < <(net_mirrors_for_raw "$MODULE_FISHER_BOOTSTRAP_REPO" \
    "$MODULE_FISHER_BOOTSTRAP_COMMIT" "$MODULE_FISHER_BOOTSTRAP_PATH")
net_fetch_verified "$bootstrap" "$MODULE_FISHER_BOOTSTRAP_SHA256" "${mirrors[@]}" || exit 1

mapfile -t before < <(fisher_present_files)
# XDG_CONFIG_HOME 指向临时目录：fisher 自己的簿记不落在用户的 ~/.config，插件本身
# 通过 fisher_path 落到 $FISHER_DIR（旧引擎同款）。
# 单引号里的内容整段是给 fish 的代码，$argv 不该在这里展开——要的就是字面量。
# shellcheck disable=SC2016
FISHER_RUN=('set --global fisher_path $argv[2]; source -- $argv[1]; fisher install $argv[3..-1]')
rc=0
XDG_CONFIG_HOME=$temp_config timeout 60 fish -c "${FISHER_RUN[0]}" \
    -- "$bootstrap" "$FISHER_DIR" "${MODULE_FISHER_PLUGINS[@]}" || rc=$?

# 不管成功失败都先记账：失败时已经落盘的文件同样归我们，重试才不会留垃圾。
mapfile -t after < <(fisher_present_files)
owned=("${FISHER_OWNED_FILES[@]}")
for relative in "${after[@]}"; do
    contains_word "$relative" "${owned[@]}" && continue
    contains_word "$relative" "${before[@]}" && continue
    owned+=("$relative")
done
if ((rc != 0)); then
    fisher_write_ownership 0 "${owned[@]}" || true
    error "fisher install failed (exit $rc); the files it already wrote are recorded, so a retry is safe"
    exit 1
fi
fisher_write_ownership 1 "${owned[@]}" || exit 1
printf 'fisher\tinstalled\t%s plugins in %s\n' "${#MODULE_FISHER_PLUGINS[@]}" "$FISHER_DIR"
exit 0
