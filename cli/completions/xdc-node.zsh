#compdef xdc-node
#==============================================================================
# xdc-node zsh completion script
# Install to /usr/local/share/zsh/site-functions/_xdc-node
# or add completion directory to fpath before compinit
#==============================================================================

_xdc_node() {
    local -a commands
    local -a global_opts

    commands=(
        'init:Interactive setup wizard'
        'status:Quick node status overview'
        'health:Run health check'
        'security:Run security audit'
        'update:Check and apply version updates'
        'backup:Trigger backup'
        'restore:Restore from backup'
        'logs:Tail node logs'
        'restart:Graceful node restart'
        'stop:Stop node'
        'start:Start node'
        'config:View/edit configuration'
        'notify:Test notifications or send alert'
        'dashboard:Start web dashboard'
        'version:Show CLI and client versions'
        'help:Show help message'
    )

    global_opts=(
        '--json[Output in JSON format]'
        '--quiet[Suppress non-essential output]'
        '--verbose[Show detailed output]'
        '--no-color[Disable colored output]'
    )

    _arguments -C \
        $global_opts \
        '1: :->command' \
        '*:: :->args'

    case $state in
        command)
            _describe -t commands 'xdc-node commands' commands
            ;;
        args)
            case $words[1] in
                init)
                    _arguments \
                        '--quick[Minimal setup with defaults]' \
                        '--help[Show help]'
                    ;;
                status)
                    _arguments \
                        '(-w --watch)'{-w,--watch}'[Auto-refresh every 5 seconds]' \
                        '--interval[Refresh interval in seconds]:seconds:(1 2 5 10 30 60)' \
                        '--json[Output in JSON format]' \
                        '--help[Show help]'
                    ;;
                health)
                    _arguments \
                        '--full[Run comprehensive health check]' \
                        '--notify[Send notification with results]' \
                        '--security-only[Only run security checks]' \
                        '--json[Output in JSON format]' \
                        '--help[Show help]'
                    ;;
                security)
                    _arguments \
                        '--audit-only[Check only, no changes]' \
                        '--fix[Apply recommended fixes]' \
                        '--json[Output in JSON format]' \
                        '--help[Show help]'
                    ;;
                update)
                    _arguments \
                        '--check[Check only, no apply]' \
                        '--apply[Download and install]' \
                        '--client[Specific client]:client:(XDPoSChain erigon-xdc)' \
                        '--json[Output in JSON format]' \
                        '--help[Show help]'
                    ;;
                backup)
                    _arguments \
                        '--full[Full backup]' \
                        '--incremental[Incremental backup]' \
                        '--encrypt[Encrypt with GPG]' \
                        '--upload[Upload to remote storage]' \
                        '--list[Show available backups]' \
                        '--json[Output in JSON format]' \
                        '--help[Show help]'
                    ;;
                restore)
                    _arguments \
                        '--help[Show help]' \
                        '1:backup file:_files -g "*.tar.gz"'
                    ;;
                logs)
                    _arguments \
                        '(-n --lines)'{-n,--lines}'[Number of lines]:lines:(10 25 50 100 200 500 1000)' \
                        '(-f --follow)'{-f,--follow}'[Follow log output]' \
                        '--client[Client logs]:client:(geth erigon)' \
                        '--help[Show help]'
                    ;;
                restart)
                    _arguments \
                        '--graceful[Wait for block, then restart]' \
                        '--force[Immediate restart]' \
                        '--help[Show help]'
                    ;;
                stop)
                    _arguments '--help[Show help]'
                    ;;
                start)
                    _arguments '--help[Show help]'
                    ;;
                config)
                    local -a config_cmds
                    config_cmds=(
                        'list:Show all config'
                        'get:Get specific value'
                        'set:Set value'
                    )
                    local -a config_keys
                    config_keys=(
                        'rpc_url:RPC endpoint URL'
                        'network:Network type'
                        'client:Client name'
                        'auto_update:Enable auto-updates'
                        'telegram_enabled:Enable Telegram'
                        'telegram_bot_token:Telegram token'
                        'telegram_chat_id:Telegram chat ID'
                    )
                    
                    _arguments -C \
                        '--json[Output in JSON format]' \
                        '--help[Show help]' \
                        '1: :->config_cmd' \
                        '*:: :->config_args'
                    
                    case $state in
                        config_cmd)
                            _describe -t config_cmds 'config subcommands' config_cmds
                            ;;
                        config_args)
                            case $words[1] in
                                get|set)
                                    _describe -t config_keys 'config keys' config_keys
                                    ;;
                            esac
                            ;;
                    esac
                    ;;
                notify)
                    _arguments \
                        '--test[Test all channels]' \
                        '--send[Send message]:message:' \
                        '--level[Alert level]:level:(critical warning info)' \
                        '--help[Show help]'
                    ;;
                dashboard)
                    _arguments \
                        '--port[Port number]:port:(3000 8080 8000 9000)' \
                        '--help[Show help]'
                    ;;
                version)
                    _arguments \
                        '--json[Output in JSON format]' \
                        '--help[Show help]'
                    ;;
                help)
                    _describe -t commands 'xdc-node commands' commands
                    ;;
            esac
            ;;
    esac
}

_xdc_node "$@"
