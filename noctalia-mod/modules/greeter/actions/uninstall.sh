#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# 卸：把登录界面还给这台机器原来的样子。
#
# 顺序也是反的同一套讲究：先关 greetd、再放回上一个显示管理器，最后才还原文件——
# 中间任何一步失败都把 greetd 重新 enable 回来并报错，不留一个"没有登录管理器"的机器。
#
# 与旧引擎的一处有意差别：记录文件里没有上一个显示管理器时，这里照样关掉 greetd
# （并说明没有别的要放回）。旧引擎在这种情况下拒绝卸载，用户会被卡住。
source "$(dirname -- "${BASH_SOURCE[0]}")/_common.sh"

command -v systemctl >/dev/null 2>&1 || {
    error 'systemctl is required to uninstall the greeter'
    exit 1
}

previous_dm=''
if [[ -e $GREETER_DM_RECORD ]]; then
    previous_dm=$(greeter_recorded_dm) || {
        error "$GREETER_DM_RECORD does not name a known display manager; refusing to touch the login manager"
        exit 1
    }
fi

if system_unit_enabled greetd; then
    if ! system_unit_disable greetd; then
        error 'could not disable greetd; leaving the system as it was'
        system_unit_enable greetd yes || error 'greetd is in an unknown state; check systemctl status greetd'
        exit 1
    fi
    printf 'greetd\tdisabled\tlogin manager\n'
else
    printf 'greetd\talready disabled\tlogin manager\n'
fi

if [[ -n $previous_dm ]]; then
    if ! system_unit_enable "$previous_dm" yes; then
        error "could not re-enable $previous_dm; putting greetd back so the machine still has a login manager"
        system_unit_enable greetd yes || error 'greetd is in an unknown state; check systemctl status greetd'
        exit 1
    fi
    printf 'display-manager\t%s re-enabled\n' "$previous_dm"
else
    printf 'display-manager\tnone recorded\tnothing to re-enable\n'
fi

# config.toml：有备份就放回备份；没有备份说明这个文件原来不存在（备份只在原文件存在时
# 才会建），那就在确认它确实是我们写的那份之后删掉——不把一个指向已卸载 greeter 的
# 配置留在 /etc 里。
if [[ -e $GREETER_CONFIG.noctalia-mod.bak ]]; then
    system_restore_root_file "$GREETER_CONFIG" || {
        error "could not restore $GREETER_CONFIG"
        exit 1
    }
    printf 'config\trestored\t%s\n' "$GREETER_CONFIG"
elif [[ -f $GREETER_CONFIG ]] && grep -q 'noctalia-greeter-session' "$GREETER_CONFIG"; then
    system_clear_root_file "$GREETER_CONFIG" || exit 1
    printf 'config\tremoved (it did not exist before)\t%s\n' "$GREETER_CONFIG"
else
    printf 'config\tleft alone\t%s is not ours\n' "$GREETER_CONFIG"
fi

if [[ -e $GREETER_POLKIT_RULE.noctalia-mod.bak ]]; then
    system_restore_root_file "$GREETER_POLKIT_RULE" || {
        error "could not restore $GREETER_POLKIT_RULE"
        exit 1
    }
    printf 'polkit\trestored\t%s\n' "$GREETER_POLKIT_RULE"
else
    system_clear_root_file "$GREETER_POLKIT_RULE" || exit 1
    printf 'polkit\tremoved\t%s\n' "$GREETER_POLKIT_RULE"
fi

sudo rm -rf -- "$GREETER_STATE_DIR" || {
    error "could not remove $GREETER_STATE_DIR"
    exit 1
}
printf 'state-dir\tremoved\t%s\n' "$GREETER_STATE_DIR"

system_clear_root_file "$GREETER_DM_RECORD" || exit 1
printf 'record\tremoved\t%s\n' "$GREETER_DM_RECORD"
printf 'note\tpackages are kept\tgreetd and noctalia-greeter stay installed\n'
exit 0
