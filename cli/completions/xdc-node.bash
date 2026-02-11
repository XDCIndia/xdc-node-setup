#!/usr/bin/env bash
#==============================================================================
# xdc-node bash completion script
# Source this file or install to /etc/bash_completion.d/xdc-node
#==============================================================================

_xdc_node_completions() {
    local cur prev words cword
    _init_completion || return

    local commands="init status health security update backup restore logs restart stop start config notify dashboard version help"
    
    # Global options
    local global_opts="--json --quiet --verbose --no-color"
    
    # Command-specific options
    local init_opts="--quick --help"
    local status_opts="--watch --interval --json --help"
    local health_opts="--full --notify --security-only --json --help"
    local security_opts="--audit-only --fix --json --help"
    local update_opts="--check --apply --client --json --help"
    local backup_opts="--full --incremental --encrypt --upload --list --json --help"
    local restore_opts="--help"
    local logs_opts="--lines --follow --client --help"
    local restart_opts="--graceful --force --help"
    local stop_opts="--help"
    local start_opts="--help"
    local config_opts="list get set --json --help"
    local notify_opts="--test --send --level --help"
    local dashboard_opts="--port --help"
    local version_opts="--json --help"

    # Config keys for 'config get/set'
    local config_keys="rpc_url network client auto_update telegram_enabled telegram_bot_token telegram_chat_id"
    
    # Notification levels
    local notify_levels="critical warning info"
    
    # Clients
    local clients="XDPoSChain erigon-xdc"

    case "${cword}" in
        1)
            # First argument - complete commands
            COMPREPLY=($(compgen -W "${commands}" -- "${cur}"))
            return 0
            ;;
        *)
            # Handle command-specific completions
            case "${words[1]}" in
                init)
                    COMPREPLY=($(compgen -W "${init_opts}" -- "${cur}"))
                    ;;
                status)
                    case "${prev}" in
                        --interval)
                            COMPREPLY=($(compgen -W "1 2 5 10 30 60" -- "${cur}"))
                            ;;
                        *)
                            COMPREPLY=($(compgen -W "${status_opts}" -- "${cur}"))
                            ;;
                    esac
                    ;;
                health)
                    COMPREPLY=($(compgen -W "${health_opts}" -- "${cur}"))
                    ;;
                security)
                    COMPREPLY=($(compgen -W "${security_opts}" -- "${cur}"))
                    ;;
                update)
                    case "${prev}" in
                        --client)
                            COMPREPLY=($(compgen -W "${clients}" -- "${cur}"))
                            ;;
                        *)
                            COMPREPLY=($(compgen -W "${update_opts}" -- "${cur}"))
                            ;;
                    esac
                    ;;
                backup)
                    COMPREPLY=($(compgen -W "${backup_opts}" -- "${cur}"))
                    ;;
                restore)
                    # Complete backup files
                    if [[ "${prev}" == "restore" ]]; then
                        local backup_dir="/backup/xdc-node"
                        if [[ -d "$backup_dir" ]]; then
                            COMPREPLY=($(compgen -f "${backup_dir}/" -- "${cur}"))
                        else
                            COMPREPLY=($(compgen -f -- "${cur}"))
                        fi
                    else
                        COMPREPLY=($(compgen -W "${restore_opts}" -- "${cur}"))
                    fi
                    ;;
                logs)
                    case "${prev}" in
                        --lines|-n)
                            COMPREPLY=($(compgen -W "10 25 50 100 200 500 1000" -- "${cur}"))
                            ;;
                        --client)
                            COMPREPLY=($(compgen -W "geth erigon" -- "${cur}"))
                            ;;
                        *)
                            COMPREPLY=($(compgen -W "${logs_opts}" -- "${cur}"))
                            ;;
                    esac
                    ;;
                restart)
                    COMPREPLY=($(compgen -W "${restart_opts}" -- "${cur}"))
                    ;;
                stop)
                    COMPREPLY=($(compgen -W "${stop_opts}" -- "${cur}"))
                    ;;
                start)
                    COMPREPLY=($(compgen -W "${start_opts}" -- "${cur}"))
                    ;;
                config)
                    case "${words[2]}" in
                        get)
                            COMPREPLY=($(compgen -W "${config_keys}" -- "${cur}"))
                            ;;
                        set)
                            if [[ ${cword} -eq 3 ]]; then
                                COMPREPLY=($(compgen -W "${config_keys}" -- "${cur}"))
                            fi
                            ;;
                        *)
                            COMPREPLY=($(compgen -W "${config_opts}" -- "${cur}"))
                            ;;
                    esac
                    ;;
                notify)
                    case "${prev}" in
                        --level)
                            COMPREPLY=($(compgen -W "${notify_levels}" -- "${cur}"))
                            ;;
                        --send)
                            # Don't complete - user provides message
                            ;;
                        *)
                            COMPREPLY=($(compgen -W "${notify_opts}" -- "${cur}"))
                            ;;
                    esac
                    ;;
                dashboard)
                    case "${prev}" in
                        --port)
                            COMPREPLY=($(compgen -W "3000 8080 8000 9000" -- "${cur}"))
                            ;;
                        *)
                            COMPREPLY=($(compgen -W "${dashboard_opts}" -- "${cur}"))
                            ;;
                    esac
                    ;;
                version)
                    COMPREPLY=($(compgen -W "${version_opts}" -- "${cur}"))
                    ;;
                help)
                    COMPREPLY=($(compgen -W "${commands}" -- "${cur}"))
                    ;;
                *)
                    COMPREPLY=($(compgen -W "${global_opts}" -- "${cur}"))
                    ;;
            esac
            ;;
    esac

    return 0
}

# Register completion
complete -F _xdc_node_completions xdc-node

# XDC-specific commands
_masternode_commands() {
    local commands="setup status register"
    COMPREPLY=( $(compgen -W "${commands}" -- ${cur}) )
}

_peers_commands() {
    local commands="optimize list test"
    local opts="--testnet --help"
    COMPREPLY=( $(compgen -W "${commands} ${opts}" -- ${cur}) )
}

_snapshot_commands() {
    local commands="download create verify list"
    local opts="--type --testnet --help"
    COMPREPLY=( $(compgen -W "${commands} ${opts}" -- ${cur}) )
}

_monitor_commands() {
    local commands="epoch rewards fork txpool peers block-time all"
    local opts="--testnet --watch --help"
    COMPREPLY=( $(compgen -W "${commands} ${opts}" -- ${cur}) )
}

_sync_commands() {
    local commands="status eta prune recommend compare"
    local opts="--watch --help"
    COMPREPLY=( $(compgen -W "${commands} ${opts}" -- ${cur}) )
}

_rpc_secure_commands() {
    local commands="generate audit apply list"
    local opts="--profile --help"
    COMPREPLY=( $(compgen -W "${commands} ${opts}" -- ${cur}) )
}

_network_commands() {
    local commands="peers diversity upgrade health map"
    COMPREPLY=( $(compgen -W "${commands}" -- ${cur}) )
}
