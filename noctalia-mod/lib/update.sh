# shellcheck shell=bash
# 自更新（PLAN §11 阶段 E）：拉取新版本，然后用新代码重新部署。
#
# 只对 git 检出有意义：这个项目就是一棵可以整目录取走的源码树，`update` 的语义是
# `git pull --ff-only` + 重铺已装模块。没有自动状态迁移——账本、快照、预设的 schema
# 在一个自包含项目里由代码自己保证，不需要一条按版本号走的迁移链（旧引擎那套 `migrations`
# 是给跨版本升级用的，新项目没有历史包袱）。
#
# 三条硬规矩：
#   1. 改了已跟踪文件就拒绝 —— 那可能是用户自己的改动，`git pull` 要么失败要么把它卷进
#      合并。未跟踪文件不拦（临时文件不该挡住一次更新）。
#   2. 拉完必须换进程再部署 —— lib 只在入口启动时 source 过一次，本进程里跑的仍是旧代码。
#   3. `--no-deploy` 只拉不铺，给人一个先看 diff 的余地。

# git 的网络参数与 install.sh 一致：低速率超时 + 连接超时，避免卡死在没有响应的镜像上。
UPDATE_GIT_NET=(-c http.lowSpeedLimit=1000 -c http.lowSpeedTime=15 -c http.connectTimeout=10)

UPDATE_OLD_HEAD=''
UPDATE_NEW_HEAD=''
UPDATE_CHANGED=no

update_git_dir() {
    printf '%s/.git\n' "$(project_root)"
}

update_head() {
    git -C "$(project_root)" rev-parse HEAD 2>/dev/null || return 1
}

# 只看已跟踪文件：`git status --porcelain` 默认把未跟踪文件也算进来，那会让一个路过的
# 临时文件永久挡住更新。
update_tree_is_dirty() {
    local status
    status=$(git -C "$(project_root)" status --porcelain --untracked-files=no 2>/dev/null) || return 1
    [[ -n $status ]]
}

# 成功返回 0；结果放 UPDATE_OLD_HEAD / UPDATE_NEW_HEAD / UPDATE_CHANGED。
# 那三个变量的读取点在 bin/noctalia-mod。
# shellcheck disable=SC2034
update_pull() {
    local root
    root=$(project_root)
    command -v git >/dev/null 2>&1 || {
        error 'git is required to update this checkout'
        return 1
    }
    [[ -d $(update_git_dir) ]] || {
        error "not a git checkout: $root (update it the way you installed it)"
        return 1
    }
    if update_tree_is_dirty; then
        error 'this checkout has uncommitted changes to tracked files; commit or stash them first'
        return 1
    fi
    UPDATE_OLD_HEAD=$(update_head) || {
        error 'cannot read the current commit'
        return 1
    }
    git -C "$root" "${UPDATE_GIT_NET[@]}" pull --ff-only || {
        error 'git pull failed; the checkout is unchanged'
        return 1
    }
    UPDATE_NEW_HEAD=$(update_head) || {
        error 'cannot read the commit after the pull'
        return 1
    }
    if [[ $UPDATE_NEW_HEAD == "$UPDATE_OLD_HEAD" ]]; then
        UPDATE_CHANGED=no
    else
        UPDATE_CHANGED=yes
    fi
    return 0
}

# 用新代码重新部署：exec 一个新进程，本进程里 source 过的旧 lib 就不再参与。
update_reexec_install() {
    local -a modules=() argv=()
    mapfile -t modules < <(state_enabled_modules)
    ((${#modules[@]})) || {
        log 'nothing is deployed yet; run: noctalia-mod setup'
        return 0
    }
    argv=(install "${modules[@]}")
    [[ ${UPDATE_ASSUME_YES:-no} == yes ]] && argv+=(--yes)
    exec "$NOCTALIA_MOD_ENTRY" "${argv[@]}"
}
