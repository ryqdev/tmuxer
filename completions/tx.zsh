# Source after compinit: source /path/to/tx.zsh [command-name ...]

_tx() {
    local ret=1
    local -a subcommands hosts
    local expl

    if (( CURRENT == 2 )); then
        subcommands=(
            'remote:Manage remote hosts and sessions'
            'help:Show help'
        )
        _describe -t commands 'tx command' subcommands && ret=0
        _tmux "$@" && ret=0
        return ret
    fi

    if [[ $words[2] != remote ]]; then
        [[ $words[2] == help ]] && return 1
        _tmux "$@"
        return
    fi

    if (( CURRENT == 3 )); then
        subcommands=(
            'select:Select a local or remote session'
            'list:List registered remote hosts'
            'candidates:List SSH aliases available for registration'
            'register:Register remote hosts'
            'delete:Remove hosts from the allow list'
            'exec:Run tmux on a registered host'
            'sessions:List local and remote sessions'
            'help:Show remote command help'
        )
        _describe -t commands 'remote command' subcommands
        return
    fi

    case $words[3] in
        register)
            hosts=("${(@f)$(command "$words[1]" remote candidates 2>/dev/null)}")
            [[ -n $hosts[1] ]] || return 1
            _wanted hosts expl 'SSH alias' compadd -a hosts ;;
        exec|delete)
            if [[ $words[3] == delete ]] || (( CURRENT == 4 )); then
                hosts=("${(@f)$(command "$words[1]" remote list 2>/dev/null)}")
                [[ -n $hosts[1] ]] || return 1
                _wanted hosts expl 'registered host' compadd -a hosts
            else
                _message 'remote tmux arguments'
            fi ;;
        sessions)
            local -a words=("$words[1]" "${(@)words[4,-1]}")
            local -i CURRENT=$(( CURRENT - 2 ))
            _arguments -s \
                '-L[specify socket name]:socket name:' \
                '-S[specify socket path]:socket path:_files' \
                '-f[specify configuration file]:configuration file:_files' \
                '-T[set terminal features]:terminal features:' \
                '-v[request verbose logging]' ;;
        *) return 1 ;;
    esac
}

autoload -Uz _tmux
if (( $# )); then
    compdef _tx "$@"
else
    compdef _tx tx
fi
