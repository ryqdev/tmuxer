# Source after compinit: source /path/to/tx.zsh [command-name ...]

_tx() {
    local ret=1
    local -a subcommands hosts
    local expl

    if (( CURRENT == 2 )); then
        subcommands=(
            'remote:Select remote sessions or run tmux on a registered server'
            'hosts:Manage registered servers'
            'help:Show help'
        )
        _describe -t commands 'tx command' subcommands && ret=0
        _tmux "$@" && ret=0
        return ret
    fi

    if [[ $words[2] != remote && $words[2] != hosts ]]; then
        [[ $words[2] == help ]] && return 1
        _tmux "$@"
        return
    fi

    if [[ $words[2] == hosts ]]; then
        if (( CURRENT == 3 )); then
            subcommands=(
                'list:List registered servers'
                'candidates:List SSH aliases available for registration'
                'register:Register servers'
                'remove:Remove registered servers'
                'help:Show host management help'
            )
            _describe -t commands 'hosts command' subcommands
            return
        fi
        case $words[3] in
            register)
                hosts=("${(@f)$(command "$words[1]" hosts candidates 2>/dev/null)}")
                [[ -n $hosts[1] ]] || return 1
                _wanted hosts expl 'SSH alias' compadd -a hosts ;;
            remove)
                hosts=("${(@f)$(command "$words[1]" hosts list 2>/dev/null)}")
                [[ -n $hosts[1] ]] || return 1
                _wanted hosts expl 'registered host' compadd -a hosts ;;
            *) return 1 ;;
        esac
        return
    fi

    if (( CURRENT == 3 )); then
        hosts=("${(@f)$(command "$words[1]" hosts list 2>/dev/null)}")
        if [[ -n $hosts[1] ]]; then
            hosts=("${(@)hosts/#/@}")
            _wanted hosts expl 'server reference' compadd -a hosts && ret=0
        fi
        return ret
    fi

    [[ $words[3] == @* ]] || return 1
    # Reuse tmux completion only after the required server reference.
    local -a words=("$words[1]" "${(@)words[4,-1]}")
    local -i CURRENT=$(( CURRENT - 2 ))
    _tmux "$@" && ret=0
    return ret
}

autoload -Uz _tmux
if (( $# )); then
    compdef _tx "$@"
else
    compdef _tx tx
fi
