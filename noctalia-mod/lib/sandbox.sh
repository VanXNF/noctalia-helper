# shellcheck shell=bash
# 沙箱部署测试（PLAN §11 阶段 E）：把入口完整地跑在一个临时 HOME 里。
#
# 测什么：从零铺核心集 → 再铺一遍必须收敛 → plan 不许报漂移 → uninstall 收掉账本。
# 这条链路是"全新机器上到底能不能从零跑通"的本地替身：不装包、不碰真实 ~/.config、
# 不进 niri 会话。
#
# 为什么不并在 unittest 套件里：套件按断言逐条盯内部契约（Python 子进程 + 假命令）；
# 这条命令是给人和开发机的一句话体检——它跑的是真入口、真模块、真原子替换，只在
# HOME 与 PATH 上做隔离，输出是给人看的 `step → ok/failed`。
#
# 隔离手段：临时 HOME + 一层命令替身放在 PATH 最前。替身让 pacman 报告"都装好了"
# （于是依赖阶段无事可做、不会提权、不会装包），让 niri/noctalia/gsettings 应答部署
# 收尾要问的东西。任何一步失败就保留沙箱目录并打印日志尾部——测试失败时删证据最糟。

# 替身脚本 = 固定头部（把调用记进日志）+ 调用方给的应答，两者拼成文件。
# 头部用 quoted heredoc 写：里面的 $ 与 $(...) 是留给替身进程的，不该在这里展开。
sandbox_shim() {
    local path=$1
    {
        cat <<'HEADER'
#!/usr/bin/env bash
printf '%s' "$(basename "$0")" >> "${SANDBOX_LOG:-/dev/null}"
printf ' <%s>' "$@" >> "${SANDBOX_LOG:-/dev/null}"
printf '\n' >> "${SANDBOX_LOG:-/dev/null}"
HEADER
        cat
    } > "$path" || return 1
    chmod 755 -- "$path"
}

# 每个替身都必须能正确应答查询（见 PLAN §16.4 陷阱四：只应答 -Q 的假 pacman 会让测试
# 测到替身自己）。pacman 一律答"已装"，于是依赖阶段无事可做；真被要求装包就报错，
# 不假装成功——那样才暴露得出"沙箱里居然想装包"。
sandbox_write_shims() {
    local dir=$1
    mkdir -p "$dir" || return 1
    sandbox_shim "$dir/pacman" <<'SHIM' || return 1
if [[ ${1-} == -Q ]]; then exit 0; fi
if [[ ${1-} == -S ]]; then
    printf 'sandbox: refusing to install packages\n' >&2
    exit 1
fi
exit 0
SHIM
    sandbox_shim "$dir/sudo" <<'SHIM' || return 1
if [[ ${1-} == -v ]]; then exit 0; fi
exec "$@"
SHIM
    sandbox_shim "$dir/niri" <<'SHIM' || return 1
exit 0
SHIM
    sandbox_shim "$dir/noctalia" <<'SHIM' || return 1
if [[ ${1-} == msg && ${2-} == theme-mode-get ]]; then
    printf 'dark\n'
fi
exit 0
SHIM
    sandbox_shim "$dir/pkill" <<'SHIM' || return 1
exit 0
SHIM
    sandbox_shim "$dir/xdg-user-dir" <<'SHIM' || return 1
printf '%s\n' "$HOME/Pictures"
SHIM
    sandbox_shim "$dir/gsettings" <<'SHIM' || return 1
if [[ ${1-} == get ]]; then
    printf "'prefer-dark'\n"
fi
exit 0
SHIM
    return 0
}

# 部署出来的树必须有的东西：模块目标 + 模块自己声明的 MODULE_VALIDATE_PATHS。
# 目标路径按沙箱的配置根拼，不能用 safe_target_path——那个跟着父进程的真实 HOME 走。
sandbox_verify_targets() {
    local config=$1 id target relative failed=0
    shift
    for id in "$@"; do
        if ! module_load "$id"; then
            error "sandbox: module $id no longer loads"
            failed=1
            continue
        fi
        target="$config/$MODULE_TARGET"
        if [[ ! -e $target && ! -L $target ]]; then
            error "sandbox: $id did not deploy $target"
            failed=1
        fi
        for relative in "${MODULE_VALIDATE_PATHS[@]}"; do
            if [[ ! -e $target/$relative && ! -L $target/$relative ]]; then
                error "sandbox: $id is missing $relative after the deploy"
                failed=1
            fi
        done
    done
    return "$failed"
}

# 整棵配置树的摘要：内容 + 软链指向，不含 mtime（重跑会重写文件，时间戳必然不同）。
sandbox_tree_hash() {
    local root=$1
    (
        cd -- "$root" || exit 1
        find . \( -type f -o -type l \) -print0 | LC_ALL=C sort -z |
            while IFS= read -r -d '' path; do
                printf '%s\0' "$path"
                if [[ -L $path ]]; then
                    printf 'link\0%s\0' "$(readlink -- "$path")"
                else
                    sha256sum < "$path" | cut -d' ' -f1
                    printf '\0'
                fi
            done | sha256sum | cut -d' ' -f1
    )
}

# 沙箱里任何叫 *noctalia-mod.* 的东西都是我们自己的残渣：那棵树是这一轮刚建的。
sandbox_staging_residue() {
    find "$1" -depth -name '*noctalia-mod.*' -print 2>/dev/null
}

sandbox_fail() {
    local message=$1 log=$2
    error "sandbox test: $message"
    [[ -f $log ]] && tail -n 15 -- "$log" >&2
    printf 'test\tfailed\t%s\n' "$message"
    return 0
}

sandbox_execute() {
    local root=$1 home=$1/home shims=$1/shims log=$1/commands.log
    local before after
    local -a cli_env=() modules=() residue=()
    mkdir -p "$home/.config" "$home/.cache" "$home/.local/state" "$home/runtime" "$shims" || return 1
    sandbox_write_shims "$shims" || return 1
    cli_env=(
        "HOME=$home"
        "XDG_CONFIG_HOME=$home/.config"
        "XDG_STATE_HOME=$home/.local/state"
        "XDG_CACHE_HOME=$home/.cache"
        "XDG_RUNTIME_DIR=$home/runtime"
        "SANDBOX_LOG=$log"
        "PATH=$shims:$PATH"
    )
    mapfile -t modules < <(setup_default_modules)
    printf 'sandbox\t%s\n' "$root"

    # 1. 从零铺核心集
    if ! env "${cli_env[@]}" "$NOCTALIA_MOD_ENTRY" setup --yes > "$root/setup-1.log" 2>&1; then
        sandbox_fail 'setup --yes failed' "$root/setup-1.log"
        return 1
    fi
    if ! sandbox_verify_targets "$home/.config" "${modules[@]}"; then
        sandbox_fail 'setup did not produce the expected tree' "$root/setup-1.log"
        return 1
    fi
    printf 'step\tsetup\tok (%s)\n' "$(join_by ' ' "${modules[@]}")"
    before=$(sandbox_tree_hash "$home/.config")

    # 2. 再铺一遍必须收敛：树一模一样，且不留暂存残渣
    if ! env "${cli_env[@]}" "$NOCTALIA_MOD_ENTRY" setup --yes > "$root/setup-2.log" 2>&1; then
        sandbox_fail 'the second setup --yes failed' "$root/setup-2.log"
        return 1
    fi
    after=$(sandbox_tree_hash "$home/.config")
    if [[ $before != "$after" ]]; then
        sandbox_fail 'the second setup changed a tree that was already deployed' "$root/setup-2.log"
        return 1
    fi
    mapfile -t residue < <(sandbox_staging_residue "$home/.config")
    if ((${#residue[@]})); then
        error "sandbox: staging residue left behind: $(join_by ' ' "${residue[@]}")"
        sandbox_fail 'a staging path survived a successful deploy' "$root/setup-2.log"
        return 1
    fi
    printf 'step\tsetup again\tok (tree unchanged, no staging residue)\n'

    # 3. 刚铺完就报漂移，说明指纹或部署有一边是错的
    if ! env "${cli_env[@]}" "$NOCTALIA_MOD_ENTRY" plan "${modules[@]}" > "$root/plan.log" 2>&1; then
        sandbox_fail 'plan failed after a deploy' "$root/plan.log"
        return 1
    fi
    if grep -q '^drift' "$root/plan.log"; then
        error 'sandbox: plan reports drift right after a deploy:'
        grep '^drift' "$root/plan.log" >&2
        sandbox_fail 'a freshly deployed module reports drift' "$root/plan.log"
        return 1
    fi
    printf 'step\tplan\tok (no drift)\n'

    # 4. 卸载：账本必须清空。文件是否被删取决于恢复点，那是 §6 的语义，不在这一步断言。
    #    这里连跑过两次 setup，最近一次部署前快照就是"上一次铺好的样子"，所以文件本来
    #    就还在——这条命令验的是卸载自己的账本与恢复路径能不能走通。
    if ! env "${cli_env[@]}" "$NOCTALIA_MOD_ENTRY" uninstall --yes > "$root/uninstall.log" 2>&1; then
        sandbox_fail 'uninstall --yes failed' "$root/uninstall.log"
        return 1
    fi
    mapfile -t residue < <(find "$home/.local/state/noctalia-mod/modules" -name '*.state' -print 2>/dev/null)
    if ((${#residue[@]})); then
        error "sandbox: uninstall left ledger entries: $(join_by ' ' "${residue[@]}")"
        sandbox_fail 'uninstall left the module ledger behind' "$root/uninstall.log"
        return 1
    fi
    printf 'step\tuninstall\tok (ledger cleared)\n'
    printf 'test\tok\tfresh setup, re-run, drift and uninstall all behaved\n'
    return 0
}

# 失败时保留沙箱目录：删掉证据只会让人再去猜一遍。
sandbox_run() {
    local root='' rc=0 prefix
    prefix="${TMPDIR:-/tmp}/noctalia-mod-test."
    root=$(mktemp -d "${prefix}XXXXXX") || {
        error 'cannot create a sandbox directory'
        return 1
    }
    # 删除路径只从"刚建出来的那个前缀 + 非空"两重校验里取。
    case $root in
        "$prefix"*) ;;
        *)
            error "refusing to clean an unexpected sandbox path: $root"
            return 1
            ;;
    esac
    sandbox_execute "$root" || rc=$?
    if ((rc == 0)); then
        rm -rf -- "$root"
    else
        printf 'sandbox\tkept for inspection\t%s\n' "$root"
    fi
    return "$rc"
}
