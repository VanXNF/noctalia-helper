#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# 装：把 Noctalia Greeter 配成登录界面。
#
# 顺序是有讲究的：先把能失败的事做完（找可信的 session 可执行文件、存预先状态、建备份），
# 再写文件；文件写失败或 systemd 切换失败都走同一条回滚。已经 enable 过 greetd 的机器上
# 只补配置、不动显示管理器（重装不会把记录文件删掉）。
source "$(dirname -- "${BASH_SOURCE[0]}")/_common.sh"

# 1. session 命令必须落在 root 拥有、别人写不了的系统目录里——它会被写进 root 读的
#    配置并被 root 执行。这个检查在动任何特权操作之前做。
session_bin=$(system_trusted_executable "$(command -v noctalia-greeter-session 2>/dev/null || true)") || {
    error 'noctalia-greeter-session was not found as a trusted executable under /usr/bin'
    error 'install the packages first: noctalia-mod deps greeter'
    exit 1
}
session_arg=$(greeter_session_argument)
if [[ -n $session_arg ]]; then
    command_str="$session_bin $session_arg"
else
    command_str="$session_bin"
fi
config_content="[terminal]
vt = 1

[default_session]
command = \"$command_str\"
user = \"greeter\"
"

# 2. 存预先状态 + 建备份。备份失败就什么都还没写，直接退出。
work=$(mktemp -d) || exit 1
trap 'rm -rf -- "$work"' EXIT
greeter_capture_prestate "$work" || {
    error 'could not read the current greeter configuration'
    exit 1
}
greeter_create_backups "$work" || {
    error 'could not back up the current greeter configuration'
    exit 1
}

# 3. 写配置、建状态目录、装 polkit 规则。任何一步失败都回滚到第 2 步记下的样子。
if ! system_write_root_text "$config_content" "$GREETER_CONFIG" 644; then
    error "could not write $GREETER_CONFIG"
    greeter_rollback "$work" || error 'rollback failed; inspect /etc/greetd by hand'
    exit 1
fi
printf 'config\twritten\t%s\n' "$GREETER_CONFIG"

if ! sudo install -d -o greeter -g greeter -m 755 -- "$GREETER_STATE_DIR"; then
    error "could not create $GREETER_STATE_DIR"
    greeter_rollback "$work" || error 'rollback failed; inspect /etc/greetd by hand'
    exit 1
fi
printf 'state-dir\tready\t%s\n' "$GREETER_STATE_DIR"

# polkit 规则：让 wheel 组里的人在登录界面同步外观。动作 id 与上游二进制里的完全一致。
polkit_rule="polkit.addRule(function(action, subject) {
    if (action.id == \"org.noctalia.greeter.sync-appearance\" &&
        subject.isInGroup(\"wheel\")) {
        return polkit.Result.YES;
    }
});
"
if ! system_write_root_text "$polkit_rule" "$GREETER_POLKIT_RULE" 644; then
    error "could not write $GREETER_POLKIT_RULE"
    greeter_rollback "$work" || error 'rollback failed; inspect /etc/greetd by hand'
    exit 1
fi
printf 'polkit\twritten\t%s\n' "$GREETER_POLKIT_RULE"

# 4. greetd 得真的装了才谈得上 enable。
if ! command -v systemctl >/dev/null 2>&1 || ! systemctl cat greetd >/dev/null 2>&1; then
    error 'greetd.service is not installed; run: noctalia-mod deps greeter'
    greeter_rollback "$work" || error 'rollback failed; inspect /etc/greetd by hand'
    exit 1
fi

# 5. 记录文件存在就必须是认识的名字：坏记录说明有人动过它，不能拿它去 enable 任意单元。
record_exists=no
[[ -e $GREETER_DM_RECORD ]] && record_exists=yes
if [[ $record_exists == yes ]]; then
    recorded_dm=$(greeter_recorded_dm) || {
        error "$GREETER_DM_RECORD does not name a known display manager; refusing to touch the login manager"
        greeter_rollback "$work" || error 'rollback failed; inspect /etc/greetd by hand'
        exit 1
    }
fi

# 6. 已经 enable 过就不用再切：配置已经补齐，记录文件原样留着。
if system_unit_enabled greetd; then
    printf 'greetd\talready enabled\t%s\n' "$GREETER_CONFIG"
    printf 'next\treboot (or log out) to see the greeter\n'
    exit 0
fi

# 7. 切换显示管理器。谁在占着就先记下来，失败时按它放回去。
previous_dm=$(greeter_conflicting_dm) || previous_dm=''
if [[ -n $previous_dm ]]; then
    # 644：这个记录只是一行显示管理器名字，不是秘密；让它可读，`status` / `doctor`
    # 就不必为了看一眼它去提权（PLAN §11 阶段 F）。
    if ! system_write_root_text "$previous_dm"$'\n' "$GREETER_DM_RECORD" 644; then
        error "could not record $previous_dm in $GREETER_DM_RECORD"
        greeter_rollback "$work" || error 'rollback failed; inspect /etc/greetd by hand'
        exit 1
    fi
    printf 'display-manager\t%s will be disabled\t%s\n' "$previous_dm" "$GREETER_DM_RECORD"
fi
rollback_dm=$previous_dm
[[ -n $rollback_dm ]] || rollback_dm=${recorded_dm:-}

switched=no
if [[ -z $previous_dm ]] || system_unit_disable "$previous_dm"; then
    system_unit_enable greetd && switched=yes
fi
if [[ $switched == no ]]; then
    error 'could not enable greetd'
    greeter_restore_display_manager "$rollback_dm" ||
        error "could not restore the previous display manager; greetd state was left as found"
    # 记录文件是这次新建的、或者记的就是刚放回去的那个，都留着——重试 install 会用上它。
    greeter_rollback "$work" || error 'rollback failed; inspect /etc/greetd by hand'
    exit 1
fi
printf 'greetd\tenabled\t%s\n' "$GREETER_CONFIG"
printf 'next\treboot (or log out) to see the greeter\n'
exit 0
