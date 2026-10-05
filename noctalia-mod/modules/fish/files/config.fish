if test -f /usr/share/cachyos-fish-config/cachyos-config.fish
    source /usr/share/cachyos-fish-config/cachyos-config.fish
end

# 代理配置 (Proxy Configuration) — 修改此处以适配你的代理端口
set -g PROXY_ADDR "127.0.0.1:7890"

# 开启代理 (支持自定义端口或地址，如: proxy_on 10808 或 proxy_on 192.168.1.5:7890)
function proxy_on
    set -l addr "$PROXY_ADDR"
    if test (count $argv) -gt 0
        if string match -r '^\d+$' -- $argv[1]
            set addr "127.0.0.1:$argv[1]"
        else
            set addr "$argv[1]"
        end
    end

    set -gx http_proxy "http://$addr"
    set -gx https_proxy "http://$addr"
    set -gx all_proxy "socks5://$addr"
    set -gx HTTP_PROXY "http://$addr"
    set -gx HTTPS_PROXY "http://$addr"
    set -gx ALL_PROXY "socks5://$addr"
    echo "[+] 终端代理已开启 (Proxy: $addr)"
end

# 关闭代理
function proxy_off
    set -e http_proxy
    set -e https_proxy
    set -e all_proxy
    set -e HTTP_PROXY
    set -e HTTPS_PROXY
    set -e ALL_PROXY
    echo "[-] 终端代理已关闭"
end

# 查看代理状态
function proxy_status
    echo "--- 代理环境变量 (Proxy Env) ---"
    for var in http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY
        if set -q $var
            echo "$var: "$$var
        else
            echo "$var: [未设置]"
        end
    end

    echo ""
    echo "--- 连通性测试 (Connectivity) ---"
    echo -n "测试 Google.com... "
    set -l start (date +%s%3N)
    set -l code (curl -I -s --connect-timeout 3 -o /dev/null -w "%{http_code}" https://www.google.com 2>/dev/null)
    set -l end (date +%s%3N)
    if test "$code" = "200" -o "$code" = "301" -o "$code" = "302"
        set -l duration (math $end - $start)
        echo "成功 (HTTP $code, $duration ms)"
    else
        echo "失败"
    end

    echo -n "测试 GitHub.com... "
    set -l gh_start (date +%s%3N)
    set -l gh_code (curl -I -s --connect-timeout 3 -o /dev/null -w "%{http_code}" https://github.com 2>/dev/null)
    set -l gh_end (date +%s%3N)
    if test "$gh_code" = "200" -o "$gh_code" = "301" -o "$gh_code" = "302"
        set -l gh_duration (math $gh_end - $gh_start)
        echo "成功 (HTTP $gh_code, $gh_duration ms)"
    else
        echo "失败"
    end

    echo ""
    echo "--- IP 地理位置 (IP Location) ---"
    curl -s --connect-timeout 3 -m 3 cip.cc 2>/dev/null | head -n 3
end

function ask_agy
    proxy_on
    agy $argv
end

if status is-interactive
    # No greeting
    set fish_greeting

    # Tab 智能自动补全：优先采纳灰色历史建议，无建议时触发 Tab 列表补全
    # 注：必须用 commandline --showing-suggestion 判断，不能用 -f accept-autosuggestion
    # （后者只是把动作塞进队列并恒返回 true，会导致 else 分支永不执行、文件补全失效）
    function custom_tab_complete
        if commandline --showing-suggestion
            commandline -f accept-autosuggestion
        else
            commandline -f complete
        end
    end

    function fish_user_key_bindings
        # 绑定 Tab 键
        bind \t custom_tab_complete
        # Ctrl+V 粘贴系统剪贴板（fzf.fish 默认把 Ctrl+V 占用为变量搜索，此处覆盖回粘贴；
        # fish_user_key_bindings 在插件绑定之后执行，覆盖是时序保证的）
        bind \cv fish_clipboard_paste
        bind -M insert \cv fish_clipboard_paste
    end

    # Use starship prompt (Disable in pure TTY to avoid Nerd Font square boxes)
    if test "$TERM" != "linux"; and command -v starship &>/dev/null
        starship init fish | source
    end

    # Aliases
    alias clear "printf '\033[2J\033[3J\033[1;1H'" # fix: kitty doesn't clear scrollback properly
    alias celar "printf '\033[2J\033[3J\033[1;1H'"
    alias claer "printf '\033[2J\033[3J\033[1;1H'"

    if command -v eza &>/dev/null
        if test "$TERM" != "linux"
            alias ls 'eza --icons=auto'
        else
            alias ls 'eza'
        end
    end
end
