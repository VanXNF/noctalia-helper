# Completion for the standalone noctalia-mod configuration manager.

complete -c noctalia-mod -f -n "__fish_use_subcommand" -a "list plan install preset part snapshot rollback uninstall status"
complete -c noctalia-mod -f -n "__fish_seen_subcommand_from plan install uninstall" -a "(noctalia-mod list | string split -f1 \t)"
complete -c noctalia-mod -f -n "__fish_seen_subcommand_from install uninstall" -l yes -d "Confirm configuration changes"
complete -c noctalia-mod -f -n "__fish_seen_subcommand_from snapshot" -a "list delete"
complete -c noctalia-mod -f -n "__fish_seen_subcommand_from rollback" -a "(noctalia-mod snapshot list | string split -f1 \t)"
complete -c noctalia-mod -f -n "__fish_seen_subcommand_from preset" -a "(noctalia-mod list | string split -f1 \t)"
complete -c noctalia-mod -f -n "__fish_seen_subcommand_from part" -a "(noctalia-mod list | string split -f1 \t)"
