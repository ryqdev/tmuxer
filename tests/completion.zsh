#!/usr/bin/env zsh
# Exercise actual Tab completion in an isolated interactive Zsh.
setopt errexit nounset
zmodload zsh/zpty

completion_file=$1
command_name=$2
result_file=$TMPDIR/completion-result
terminal_output=
zsh_command=${commands[zsh]}
rm -f -- "$result_file"
zpty -b completion-shell "$zsh_command" -df
trap 'zpty -d completion-shell' EXIT

wait_for_result() {
    local deadline=$(( SECONDS + 10 ))
    local output
    while [[ ! -f $result_file ]]; do
        if (( SECONDS >= deadline )); then
            print -u2 'Timed out waiting for Zsh completion'
            while zpty -r -t completion-shell output; do print -u2 -r -- "$output"; done
            return 1
        fi
        # Drain the PTY so a full terminal buffer cannot block the child.
        while zpty -r -t completion-shell output; do terminal_output+=$output; done
        sleep 0.01
    done
}

# Capture the edited command without executing it or contacting remote hosts.
setup="autoload -Uz compinit; compinit -D -i; source ${(q)completion_file} ${(q)command_name}; PS1='> '; capture_line() { print -r -- \"\$BUFFER\" > ${(q)result_file}; BUFFER=; CURSOR=0; zle reset-prompt; }; zle -N capture_line; bindkey '^I' expand-or-complete; bindkey '^X' capture_line; print ready > ${(q)result_file}"
zpty -w completion-shell "$setup"
wait_for_result

check_completion() {
    local input=$1 wanted=$2 actual
    terminal_output=
    rm -f -- "$result_file"
    zpty -w -n completion-shell "$input"$'\t\x18'
    wait_for_result
    actual=$(< "$result_file")
    if [[ ${actual% } != $wanted ]]; then
        print -u2 -r -- "Completion mismatch: ${(qq)input} -> ${(qq)actual}; expected ${(qq)wanted}"
        print -u2 -r -- "$terminal_output"
        return 1
    fi
}

check_completion "$command_name rem" "$command_name remote"
for subcommand in candidates select list register delete exec sessions help; do
    check_completion "$command_name remote ${subcommand[1,3]}" "$command_name remote $subcommand"
done
check_completion "$command_name remote register conf" "$command_name remote register configured"
check_completion "$command_name remote register configured sec" "$command_name remote register configured second"
check_completion "$command_name remote exec reg" "$command_name remote exec registered"
check_completion "$command_name remote exec user@" "$command_name remote exec user@2001:db8::1"
check_completion "$command_name remote exec conf" "$command_name remote exec conf"
check_completion "$command_name remote delete reg" "$command_name remote delete registered"
check_completion "$command_name remote delete registered user@" "$command_name remote delete registered user@2001:db8::1"
check_completion "$command_name remote delete conf" "$command_name remote delete conf"
check_completion "$command_name remote exec reg ignored" "$command_name remote exec reg ignored"
check_completion "$command_name new-s" "$command_name new-session"
check_completion "$command_name -L socket new-s" "$command_name -L socket new-session"
check_completion "$command_name remote sessions -S ${TMPDIR:A}/sock" "$command_name remote sessions -S ${TMPDIR:A}/socket-file"
