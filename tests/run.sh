#!/usr/bin/env bash
# No bats dependency. script(1) supplies a PTY; real tmux uses isolated sockets.
set -eu

TEST_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TR=$TEST_ROOT/tx
TEST_BASH=${TEST_BASH:-$BASH}
ORIGINAL_PATH=${ORIGINAL_PATH:-$PATH}
REAL_TMUX=${REAL_TMUX:-$(command -v tmux || :)}
unset BASH_ENV ENV

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_args() {
    local file=$1
    shift
    [ -f "$file" ] || fail "missing log: $file"
    printf '%q\n' "$@" > "$CASE/expected"
    diff -u "$CASE/expected" "$file" || fail "argument mismatch: $file"
}
assert_contains() {
    local contents
    [ -f "$1" ] || fail "missing file: $1"
    contents=$(< "$1")
    case "$contents" in *"$2"*) ;; *) fail "missing text in $1: $2" ;; esac
}
assert_clean() {
    local directory
    for directory in "$TMPDIR"/tr.*; do [ ! -d "$directory" ] || fail "leaked: $directory"; done
}
assert_no_ssh() {
    local log
    for log in "$MOCK_LOG"/ssh.*; do [ ! -e "$log" ] || fail "unexpected SSH connection: $log"; done
}
assert_no_local_tmux() { [ ! -e "$MOCK_LOG/tmux.local" ] || fail 'unexpected local tmux command'; }
assert_status() {
    local wanted=$1 actual=0
    shift
    "$@" > "$CASE/out" 2> "$CASE/err" || actual=$?
    [ "$actual" -eq "$wanted" ] || fail "exit $actual, expected $wanted: $*"
}
clear_logs() { rm -f "$MOCK_LOG"/*; }
write_row() { printf '%s\n' "$2" > "$MOCK_ROWS/$1"; }
write_ssh_hosts() { printf 'Host %s\n' "$@" > "$HOME/.ssh/config"; }
run_tr() { "$TEST_BASH" "$TR" "$@"; }
minimal_path() {
    local tool
    for tool in bash awk sed mktemp rm mkdir rmdir mv sleep readlink tail script; do ln -s "$(command -v "$tool")" "$CASE/bin/$tool"; done
    PATH=$CASE/bin
    export PATH
}
run_tty() {
    command -v script >/dev/null 2>&1 || fail 'PTY tests require script(1)'
    printf 'exec ' > "$CASE/tty-command"
    printf '%q ' "$TEST_BASH" "$TR" "$@" >> "$CASE/tty-command"
    if [ -n "${TTY_STDIN-}" ]; then
        printf '< %q ' "$TTY_STDIN" >> "$CASE/tty-command"
    fi
    printf '\n' >> "$CASE/tty-command"
    if script -q -e -c ':' /dev/null </dev/null >/dev/null 2>&1; then
        local command
        printf -v command '%q %q' "$TEST_BASH" "$CASE/tty-command"
        script -q -e -c "$command" /dev/null </dev/null > "$CASE/tty-output" 2>&1
    else
        script -q /dev/null "$TEST_BASH" "$CASE/tty-command" </dev/null > "$CASE/tty-output" 2>&1
    fi
}

test_local_forward() {
    run_tr send-keys -H 'python x.py --a '\''b c'\''' '' 'a"b' '$HOME; $(touch nope)' $'two\nlines' '\path' > "$CASE/out"
    assert_args "$MOCK_LOG/tmux.local" send-keys -H 'python x.py --a '\''b c'\''' '' 'a"b' '$HOME; $(touch nope)' $'two\nlines' '\path'
    [ ! -e "$MOCK_LOG/ssh.box" ]
}
test_local_default() {
    # Local selection must not read remote configuration or require SSH.
    mkdir -p "$HOME/.config/tmuxer"
    printf 'invalid host\n' > "$HOME/.config/tmuxer/hosts"
    printf 'Host "unterminated\n' > "$HOME/.ssh/config"
    export TR_HOSTS=box TR_INTERNAL_PREVIEW=1 MOCK_PICK=$'[local]\tone\t1\tdetached'
    write_row local 'one:1:0'
    rm "$CASE/bin/ssh"
    run_tr
    assert_args "$MOCK_LOG/tmux.local" list-sessions -F '#{session_name}:#{session_windows}:#{session_attached}' attach -t '=one'
    assert_contains "$MOCK_LOG/fzf-input" "$MOCK_PICK"
    assert_no_ssh
    assert_clean
    clear_logs
    # Explicit tmux commands still work without fzf or remote configuration.
    rm "$CASE/bin/fzf"
    run_tr -L 'local socket' ls
    assert_args "$MOCK_LOG/tmux.local" -L 'local socket' ls
    export MOCK_TMUX_STATUS=37
    assert_status 37 run_tr ls
    [ ! -e "$MOCK_LOG/fzf" ]
    assert_no_ssh
}
test_local_namespace() {
    # The old wrapper commands and flags are now passed straight to local tmux.
    run_tr register box
    assert_args "$MOCK_LOG/tmux.local" register box
    [ ! -e "$HOME/.config/tmuxer/hosts" ]
    clear_logs
    run_tr delete box
    assert_args "$MOCK_LOG/tmux.local" delete box
    clear_logs
    run_tr -H box ls
    assert_args "$MOCK_LOG/tmux.local" -H box ls
    clear_logs
    run_tr -L remote -- ls
    assert_args "$MOCK_LOG/tmux.local" -L remote -- ls
    clear_logs
    run_tr --help
    assert_args "$MOCK_LOG/tmux.local" --help
    assert_no_ssh
}
test_remote_quotes() {
    write_ssh_hosts box
    run_tr hosts register box > /dev/null
    run_tr remote @box send-keys -H 'python x.py --a '\''b c'\''' '' "''''" 'a"b' '$HOME; $(touch nope)' $'two\nlines' '\path' </dev/null
    assert_args "$MOCK_LOG/tmux.box" send-keys -H 'python x.py --a '\''b c'\''' '' "''''" 'a"b' '$HOME; $(touch nope)' $'two\nlines' '\path'
    assert_contains "$MOCK_LOG/ssh.box" '-T'
    [ ! -e "$CASE/nope" ]
}
test_exit_status() {
    write_ssh_hosts box
    run_tr hosts register box > /dev/null
    export MOCK_TMUX_STATUS=37
    assert_status 37 run_tr ls
    assert_status 37 run_tr remote @box ls
}
test_global_options() {
    write_ssh_hosts box
    run_tr hosts register box > /dev/null
    run_tr -L 'local socket' ls
    assert_args "$MOCK_LOG/tmux.local" -L 'local socket' ls
    run_tr remote @box -S '/tmp/a b' -f 'my config' -T 'flags' -c 'shell command' -v capture-pane -p
    assert_args "$MOCK_LOG/tmux.box" -S '/tmp/a b' -f 'my config' -T flags -c 'shell command' -v capture-pane -p
    clear_logs
    run_tr remote @box -L -H ls
    assert_args "$MOCK_LOG/tmux.box" -L -H ls
    clear_logs
    run_tr remote @box -- send-keys -H
    assert_args "$MOCK_LOG/tmux.box" -- send-keys -H
}
test_non_tty() {
    write_ssh_hosts box
    run_tr hosts register box > /dev/null
    local command
    for command in attach attach-session a at new new-session ls capture-pane send-keys; do
        clear_logs
        run_tr remote @box "$command" </dev/null
        assert_contains "$MOCK_LOG/ssh.box" '-T'
    done
    run_tr remote @box capture-pane -p | awk '{print}' > "$CASE/piped"
    assert_contains "$CASE/piped" 'mock pane contents'
}
test_tty_attach() {
    write_ssh_hosts box
    run_tr hosts register box > /dev/null
    local command
    for command in attach attach-session a at new new-session ''; do
        clear_logs
        if [ -n "$command" ]; then run_tty remote @box -L 'socket space' "$command";
        else run_tty remote @box -S '/tmp/my socket'; fi
        assert_contains "$MOCK_LOG/ssh.box" '-t'
    done
    clear_logs
    run_tty remote @box -vLsocket -S '/tmp/my socket' -f attach -T new -c a at
    assert_contains "$MOCK_LOG/ssh.box" '-t'
}
test_tty_other() {
    write_ssh_hosts box
    run_tr hosts register box > /dev/null
    local command
    for command in ls capture-pane send-keys; do
        clear_logs
        run_tty remote @box -L attach -S new "$command"
        assert_contains "$MOCK_LOG/ssh.box" '-T'
    done
}
test_errors_help() {
    assert_status 2 run_tr hosts delete
    assert_contains "$CASE/err" 'hosts delete requires at least one host'
    assert_status 2 run_tr remote @
    assert_contains "$CASE/err" 'invalid host'
    assert_status 2 run_tr remote @-H ls
    assert_status 2 run_tr remote @all ls
    assert_status 2 run_tr hosts list extra
    assert_contains "$CASE/err" 'hosts list does not accept arguments'
    assert_status 2 run_tr hosts candidates extra
    assert_contains "$CASE/err" 'hosts candidates does not accept arguments'
    assert_status 2 run_tr hosts help extra
    assert_status 2 run_tr hosts typo
    assert_contains "$CASE/err" 'run: tx hosts help'
    assert_status 2 run_tr help extra
    assert_status 0 run_tr help
    assert_contains "$CASE/out" 'tx remote @host [tmux arguments...]'
    assert_contains "$CASE/out" 'Select a session across registered SSH hosts'
    assert_contains "$CASE/out" 'tx hosts register host'
    assert_contains "$CASE/out" 'tx hosts delete host'
    assert_contains "$CASE/out" 'tx hosts list'
    assert_contains "$CASE/out" 'tx hosts candidates'
    assert_status 0 run_tr hosts help
    assert_contains "$CASE/out" 'TR_HOSTS'
    assert_status 0 run_tr hosts
    assert_contains "$CASE/out" 'Usage: tx hosts'
    assert_no_local_tmux
    assert_no_ssh
}
test_remote_reference_names() {
    # References disambiguate even names identical to commands or namespaces.
    write_ssh_hosts ls list candidates exec help sessions select register delete remote hosts
    run_tr hosts register ls list candidates exec help sessions select register delete remote hosts > /dev/null
    rm "$CASE/bin/fzf"
    local host
    for host in ls list candidates exec help sessions select register delete remote hosts; do
        clear_logs
        run_tr remote "@$host" ls
        assert_args "$MOCK_LOG/tmux.$host" ls
    done
}
test_hosts_list() {
    write_ssh_hosts dev box
    # Missing or empty lists produce no output and do not create any files.
    run_tr hosts list > "$CASE/out"
    [ ! -s "$CASE/out" ]
    [ ! -e "$HOME/.config/tmuxer/hosts" ]
    run_tr hosts register dev box > /dev/null
    printf '# hosts\ndev\n\nbox\ndev\nuser@10.0.0.1' > "$HOME/.config/tmuxer/hosts"
    export TR_HOSTS=dev
    # Host listing is offline and is not filtered by picker settings.
    rm "$CASE/bin/tmux" "$CASE/bin/ssh" "$CASE/bin/fzf"
    minimal_path
    run_tr hosts list > "$CASE/out"
    printf '%s\n' dev box user@10.0.0.1 > "$CASE/expected"
    /usr/bin/diff -u "$CASE/expected" "$CASE/out"
    assert_no_ssh
    [ ! -e "$MOCK_LOG/tmux.local" ]
    [ ! -e "$MOCK_LOG/fzf" ]
    : > "$HOME/.config/tmuxer/hosts"
    run_tr hosts list > "$CASE/out"
    [ ! -s "$CASE/out" ]
}
test_candidates_empty() {
    run_tr hosts candidates > "$CASE/out"
    [ ! -s "$CASE/out" ]
    [ ! -e "$HOME/.ssh/config" ]
    : > "$HOME/.ssh/config"
    run_tr hosts candidates > "$CASE/out"
    [ ! -s "$CASE/out" ]
    printf '# Host hidden\nHost * !excluded\nMatch exec "touch SHOULD_NOT_RUN"\n' > "$HOME/.ssh/config"
    run_tr hosts candidates > "$CASE/out"
    [ ! -s "$CASE/out" ]
    [ ! -e "$CASE/SHOULD_NOT_RUN" ]
    [ ! -e "$HOME/.config/tmuxer/hosts" ]
    assert_no_ssh
    [ ! -e "$MOCK_LOG/tmux.local" ]
    [ ! -e "$MOCK_LOG/fzf" ]
}
test_candidates_aliases() {
    cat > "$HOME/.ssh/config" <<'CONFIG'
# Host commented
  hOsT = "dev" staging "qa" # ignored comment
    HostName real.example.com
Host dev user@10.0.0.1 2001:db8::1
Host * wildcard? !negative [pattern] -option all "bad host"
Host "$(touch SHOULD_NOT_RUN)" "back\"quote"
CONFIG
    printf '\tHOST=last\r\nHost final' >> "$HOME/.ssh/config"
    export TR_HOSTS=
    export XDG_CONFIG_HOME="$CASE/unrelated config"
    mkdir -p "$XDG_CONFIG_HOME/tmuxer"
    printf 'invalid host\n' > "$XDG_CONFIG_HOME/tmuxer/hosts"
    # Candidate listing is offline and independent of the registered hosts.
    rm "$CASE/bin/tmux" "$CASE/bin/ssh" "$CASE/bin/fzf"
    minimal_path
    run_tr hosts candidates > "$CASE/out"
    printf '%s\n' dev staging qa user@10.0.0.1 2001:db8::1 last final > "$CASE/expected"
    /usr/bin/diff -u "$CASE/expected" "$CASE/out"
    printf 'invalid host\n' > "$CASE/expected"
    /usr/bin/diff -u "$CASE/expected" "$XDG_CONFIG_HOME/tmuxer/hosts"
    [ ! -e "$CASE/SHOULD_NOT_RUN" ]
    assert_no_ssh
    [ ! -e "$MOCK_LOG/tmux.local" ]
    [ ! -e "$MOCK_LOG/fzf" ]
    # Every emitted alias can be passed directly to register.
    rm "$XDG_CONFIG_HOME/tmuxer/hosts"
    local host
    while IFS= read -r host; do run_tr hosts register "$host" > /dev/null; done < "$CASE/out"
    run_tr hosts list > "$CASE/registered"
    /usr/bin/diff -u "$CASE/out" "$CASE/registered"
}
test_candidates_includes() {
    mkdir -p "$HOME/.ssh/config.d" "$HOME/.ssh/space directory"
    cat > "$HOME/.ssh/config" <<'CONFIG'
Host first
Include config.d/*.conf "space directory/hosts #1" ~/extra.conf missing*.conf
Include config.d/a.conf
Host last first
CONFIG
    cat > "$HOME/.ssh/config.d/a.conf" <<'CONFIG'
Host alpha
Include nested.conf config.d/cycle
Match exec "touch SHOULD_NOT_RUN"
Include conditional.conf
CONFIG
    printf 'Host nested\n' > "$HOME/.ssh/nested.conf"
    printf 'Host conditional\n' > "$HOME/.ssh/conditional.conf"
    printf 'Host zeta\n' > "$HOME/.ssh/config.d/z.conf"
    printf 'Host spaced\n' > "$HOME/.ssh/space directory/hosts #1"
    printf 'Host extra\n' > "$HOME/extra.conf"
    ln -s ../config "$HOME/.ssh/config.d/cycle"
    printf 'Host absolute\nInclude config\n' > "$CASE/absolute config"
    printf 'Include="%s"\n' "$CASE/absolute config" >> "$HOME/.ssh/config"
    run_tr hosts candidates > "$CASE/out"
    printf '%s\n' first alpha nested conditional zeta spaced extra last absolute > "$CASE/expected"
    diff -u "$CASE/expected" "$CASE/out"
    [ ! -e "$CASE/SHOULD_NOT_RUN" ]
    [ ! -e "$HOME/.config/tmuxer/hosts" ]
    assert_no_ssh
    assert_clean
}
test_candidates_errors() {
    mkdir "$HOME/.ssh/config"
    assert_status 2 run_tr hosts candidates
    assert_contains "$CASE/err" 'cannot read SSH config'
    rmdir "$HOME/.ssh/config"
    printf 'Host before\nHost "unfinished\n' > "$HOME/.ssh/config"
    assert_status 2 run_tr hosts candidates
    assert_contains "$CASE/err" 'cannot parse SSH config'
    [ ! -s "$CASE/out" ]
    mkdir "$HOME/.ssh/directory"
    printf 'Host before\nInclude directory\n' > "$HOME/.ssh/config"
    assert_status 2 run_tr hosts candidates
    assert_contains "$CASE/err" 'cannot read SSH config'
    [ ! -s "$CASE/out" ]
    # Bound acyclic nesting too, so a pathological config fails clearly.
    local i
    printf 'Include depth0\n' > "$HOME/.ssh/config"
    for ((i=0; i<17; i++)); do
        printf 'Include depth%d\n' "$((i + 1))" > "$HOME/.ssh/depth$i"
    done
    printf 'Host too-deep\n' > "$HOME/.ssh/depth17"
    assert_status 2 run_tr hosts candidates
    assert_contains "$CASE/err" 'too deeply nested'
    [ ! -s "$CASE/out" ]
    assert_no_ssh
    [ ! -e "$HOME/.config/tmuxer/hosts" ]
}
test_register() {
    local mode
    write_ssh_hosts dev box staging user@10.0.0.1 2001:db8::1 offline
    run_tr hosts register dev box dev user@10.0.0.1 2001:db8::1 > "$CASE/out"
    assert_contains "$CASE/out" 'Registered: dev'
    run_tr hosts register box staging > "$CASE/out"
    printf '%s\n' dev box user@10.0.0.1 2001:db8::1 staging > "$CASE/expected"
    diff -u "$CASE/expected" "$HOME/.config/tmuxer/hosts"
    if ! mode=$(stat -c %a "$HOME/.config/tmuxer/hosts" 2>/dev/null); then
        mode=$(stat -f %Lp "$HOME/.config/tmuxer/hosts")
    fi
    [ "$mode" = 600 ]
    assert_no_ssh
    [ ! -e "$MOCK_LOG/tmux.local" ]
    [ ! -e "$MOCK_LOG/fzf" ]
    # Registration does not require tmux, SSH, fzf, or a reachable server.
    rm "$CASE/bin/tmux" "$CASE/bin/ssh" "$CASE/bin/fzf"
    minimal_path
    run_tr hosts register offline > "$CASE/out"
    assert_contains "$HOME/.config/tmuxer/hosts" offline
}
test_register_concurrent() {
    local i pid
    local -a pids
    pids=()
    write_ssh_hosts existing
    for ((i=0; i<8; i++)); do printf 'Host server-%d\n' "$i" >> "$HOME/.ssh/config"; done
    run_tr hosts register existing > /dev/null
    for ((i=0; i<8; i++)); do
        run_tr hosts register "server-$i" > "$CASE/register-$i.out" &
        pids[${#pids[@]}]=$!
    done
    for pid in "${pids[@]}"; do wait "$pid"; done
    run_tr hosts list > "$CASE/out"
    assert_contains "$CASE/out" existing
    for ((i=0; i<8; i++)); do
        assert_contains "$CASE/out" "server-$i"
    done
    [ "$(awk 'END { print NR }' "$CASE/out")" -eq 9 ] || fail 'lost or duplicated registration'
    assert_no_ssh
    assert_clean
}
test_register_invalid() {
    local host
    write_ssh_hosts dev staging
    assert_status 2 run_tr hosts register
    assert_contains "$CASE/err" 'register requires at least one host'
    for host in '' -option all '[local]' 'two hosts' $'two\nhosts' $'two\thosts' 'wild*' 'wild?' '!negative' '[pattern]' '$(touch nope)' 'host;touch nope'; do
        assert_status 2 run_tr hosts register valid "$host"
        assert_contains "$CASE/err" 'invalid host'
        [ ! -e "$HOME/.config/tmuxer/hosts" ]
    done
    [ ! -e "$CASE/nope" ]
    assert_no_ssh
    [ ! -e "$MOCK_LOG/tmux.local" ]
    # An invalid addition must leave an existing allow list unchanged.
    run_tr hosts register dev > /dev/null
    assert_status 2 run_tr hosts register staging 'bad host'
    printf 'dev\n' > "$CASE/expected"
    diff -u "$CASE/expected" "$HOME/.config/tmuxer/hosts"
}
test_register_candidates() {
    write_ssh_hosts vultr
    printf '    HostName real.example.com\nHost prod*\n' >> "$HOME/.ssh/config"
    local host
    # Reject typos, partial/case-insensitive matches, HostName values, and
    # destinations only covered by a wildcard before writing any valid input.
    for host in vult vultr-other Vultr real.example.com 192.0.2.10 user@vultr prod-other; do
        assert_status 2 run_tr hosts register vultr "$host"
        assert_contains "$CASE/err" "host is not an SSH config candidate: $host"
        assert_contains "$CASE/err" 'run: tx hosts candidates'
        [ ! -s "$CASE/out" ]
        [ ! -e "$HOME/.config/tmuxer/hosts" ]
    done
    run_tr hosts register vultr > /dev/null
    cp "$HOME/.config/tmuxer/hosts" "$CASE/before"
    assert_status 2 run_tr hosts register vult vultr
    diff -u "$CASE/before" "$HOME/.config/tmuxer/hosts"
    assert_no_ssh
    [ ! -e "$MOCK_LOG/tmux.local" ]
    [ ! -e "$MOCK_LOG/fzf" ]
}
test_register_candidates_empty() {
    assert_status 2 run_tr hosts register dev
    assert_contains "$CASE/err" 'host is not an SSH config candidate: dev'
    [ ! -e "$HOME/.config/tmuxer/hosts" ]
    : > "$HOME/.ssh/config"
    assert_status 2 run_tr hosts register dev
    [ ! -e "$HOME/.config/tmuxer/hosts" ]
    printf 'Host * !dev\nMatch exec "touch SHOULD_NOT_RUN"\n' > "$HOME/.ssh/config"
    assert_status 2 run_tr hosts register dev
    [ ! -e "$HOME/.config/tmuxer/hosts" ]
    [ ! -e "$CASE/SHOULD_NOT_RUN" ]
    assert_no_ssh
}
test_register_candidates_includes() {
    mkdir -p "$HOME/.ssh/config.d"
    printf 'Host direct\nInclude config.d/*.conf\n' > "$HOME/.ssh/config"
    printf 'Host included\nInclude nested.conf\n' > "$HOME/.ssh/config.d/one.conf"
    printf 'Host nested\n' > "$HOME/.ssh/nested.conf"
    export TR_HOSTS=
    run_tr hosts register direct included nested > "$CASE/out"
    run_tr hosts register nested included > "$CASE/out"
    run_tr hosts list > "$CASE/out"
    printf '%s\n' direct included nested > "$CASE/expected"
    diff -u "$CASE/expected" "$CASE/out"
    assert_no_ssh
}
test_register_candidates_errors() {
    write_ssh_hosts dev
    run_tr hosts register dev > /dev/null
    cp "$HOME/.config/tmuxer/hosts" "$CASE/before"
    printf 'Host dev staging\nHost "unfinished\n' > "$HOME/.ssh/config"
    assert_status 2 run_tr hosts register staging
    assert_contains "$CASE/err" 'cannot parse SSH config'
    [ ! -s "$CASE/out" ]
    diff -u "$CASE/before" "$HOME/.config/tmuxer/hosts"
    mkdir "$HOME/.ssh/unreadable-config"
    printf 'Host staging\nInclude unreadable-config\n' > "$HOME/.ssh/config"
    assert_status 2 run_tr hosts register staging
    assert_contains "$CASE/err" 'cannot read SSH config'
    [ ! -s "$CASE/out" ]
    diff -u "$CASE/before" "$HOME/.config/tmuxer/hosts"
    assert_no_ssh
}
test_register_legacy_hosts() {
    write_ssh_hosts dev
    mkdir -p "$HOME/.config/tmuxer"
    printf 'legacy\n' > "$HOME/.config/tmuxer/hosts"
    run_tr hosts register dev > /dev/null
    run_tr hosts list > "$CASE/out"
    printf '%s\n' legacy dev > "$CASE/expected"
    diff -u "$CASE/expected" "$CASE/out"
    assert_status 2 run_tr hosts register legacy
    diff -u "$CASE/expected" "$HOME/.config/tmuxer/hosts"
    assert_no_ssh
    # Candidate validation applies to registration, without revoking old entries.
    rm "$HOME/.ssh/config"
    run_tr remote @legacy ls
    assert_args "$MOCK_LOG/tmux.legacy" ls
    run_tr remote @dev ls
    assert_args "$MOCK_LOG/tmux.dev" ls
}
test_register_config_path() {
    write_ssh_hosts box dev staging
    export XDG_CONFIG_HOME="$CASE/config directory's"
    run_tr hosts register box > /dev/null
    [ -f "$XDG_CONFIG_HOME/tmuxer/hosts" ]
    [ ! -e "$HOME/.config/tmuxer/hosts" ]
    # Comments, duplicates, empty lines and an unterminated final line are safe.
    printf '# registered hosts\nbox\n\nbox\ndev' > "$XDG_CONFIG_HOME/tmuxer/hosts"
    run_tr hosts register staging > /dev/null
    printf '# registered hosts\nbox\n\nbox\ndev\nstaging\n' > "$CASE/expected"
    diff -u "$CASE/expected" "$XDG_CONFIG_HOME/tmuxer/hosts"
    run_tr hosts list > "$CASE/out"
    printf '%s\n' box dev staging > "$CASE/expected"
    diff -u "$CASE/expected" "$CASE/out"
    write_row dev 'work:1:0'
    export MOCK_PICK=$'dev\twork\t1\tdetached'
    run_tty remote
    printf '%s\n' "$MOCK_PICK" > "$CASE/expected"
    diff -u "$CASE/expected" "$MOCK_LOG/fzf-input"
    assert_args "$MOCK_LOG/tmux.dev" list-sessions -F '#{session_name}:#{session_windows}:#{session_attached}' attach -t '=work'
    assert_args "$MOCK_LOG/tmux.box" list-sessions -F '#{session_name}:#{session_windows}:#{session_attached}'
    assert_args "$MOCK_LOG/tmux.staging" list-sessions -F '#{session_name}:#{session_windows}:#{session_attached}'
    assert_clean
}
test_register_io_errors() {
    write_ssh_hosts box
    mkdir -p "$HOME/.config/tmuxer/hosts"
    assert_status 2 run_tr hosts register box
    assert_contains "$CASE/err" 'cannot read allow list'
    assert_status 2 run_tr remote
    assert_contains "$CASE/err" 'cannot read allow list'
    assert_status 2 run_tr hosts list
    assert_contains "$CASE/err" 'cannot read allow list'
    rm -rf "$HOME/.config/tmuxer"
    printf 'not a directory\n' > "$HOME/.config/tmuxer"
    assert_status 2 run_tr hosts register box
    assert_contains "$CASE/err" 'cannot write allow list'
    rm "$HOME/.config/tmuxer"
    mkdir "$HOME/.config/tmuxer"
    printf 'valid\nbad host\n' > "$HOME/.config/tmuxer/hosts"
    assert_status 2 run_tr remote
    assert_contains "$CASE/err" 'invalid host'
    assert_status 2 run_tr hosts list
    assert_contains "$CASE/err" 'invalid host'
    assert_no_ssh
    [ ! -e "$MOCK_LOG/tmux.local" ]
}
test_delete() {
    mkdir -p "$HOME/.config/tmuxer"
    printf '# remotes\n\ndev\ndev-extra\ndev\nprod\n# dev\nstaging' > "$HOME/.config/tmuxer/hosts"
    # Delete only reads the allow list, even with unusable SSH configuration.
    mkdir "$HOME/.ssh/config"
    export TR_HOSTS=
    rm "$CASE/bin/tmux" "$CASE/bin/ssh" "$CASE/bin/fzf"
    minimal_path
    run_tr hosts delete dev prod dev > "$CASE/out"
    printf '%s\n' 'Deleted: dev' 'Deleted: prod' 'Deleted: dev' > "$CASE/expected"
    /usr/bin/diff -u "$CASE/expected" "$CASE/out"
    printf '# remotes\n\ndev-extra\n# dev\nstaging\n' > "$CASE/expected"
    /usr/bin/diff -u "$CASE/expected" "$HOME/.config/tmuxer/hosts"
    run_tr hosts list > "$CASE/out"
    printf '%s\n' dev-extra staging > "$CASE/expected"
    /usr/bin/diff -u "$CASE/expected" "$CASE/out"
    run_tr hosts delete dev-extra staging > "$CASE/out"
    run_tr hosts list > "$CASE/out"
    [ ! -s "$CASE/out" ]
    printf '# remotes\n\n# dev\n' > "$CASE/expected"
    /usr/bin/diff -u "$CASE/expected" "$HOME/.config/tmuxer/hosts"
    [ ! -e "$HOME/.config/tmuxer/hosts.lock" ]
    assert_no_ssh
    [ ! -e "$MOCK_LOG/tmux.local" ]
    [ ! -e "$MOCK_LOG/fzf" ]
}
test_delete_invalid() {
    mkdir -p "$HOME/.config/tmuxer"
    printf 'dev\nstaging\n' > "$HOME/.config/tmuxer/hosts"
    cp "$HOME/.config/tmuxer/hosts" "$CASE/before"
    local host
    for host in '' -option all 'bad host' 'dev*' '$(touch nope)'; do
        assert_status 2 run_tr hosts delete dev "$host"
        assert_contains "$CASE/err" 'invalid host'
        [ ! -s "$CASE/out" ]
        diff -u "$CASE/before" "$HOME/.config/tmuxer/hosts"
    done
    assert_status 2 run_tr hosts delete dev missing
    assert_contains "$CASE/err" 'host is not registered: missing'
    assert_contains "$CASE/err" 'run: tx hosts list'
    [ ! -s "$CASE/out" ]
    diff -u "$CASE/before" "$HOME/.config/tmuxer/hosts"
    [ ! -e "$HOME/.config/tmuxer/hosts.lock" ]
    rm "$HOME/.config/tmuxer/hosts"
    assert_status 2 run_tr hosts delete dev
    [ ! -e "$HOME/.config/tmuxer/hosts" ]
    : > "$HOME/.config/tmuxer/hosts"
    assert_status 2 run_tr hosts delete dev
    [ ! -s "$HOME/.config/tmuxer/hosts" ]
    [ ! -e "$CASE/nope" ]
    assert_no_ssh
}
test_delete_config_path() {
    export XDG_CONFIG_HOME="$CASE/config directory's"
    mkdir -p "$XDG_CONFIG_HOME/tmuxer" "$CASE/linked directory"
    printf 'legacy\nuser@10.0.0.1\n2001:db8::1\n' > "$CASE/linked directory/hosts"
    ln -s "$CASE/linked directory/hosts" "$XDG_CONFIG_HOME/tmuxer/hosts-link"
    ln -s hosts-link "$XDG_CONFIG_HOME/tmuxer/hosts"
    run_tr hosts delete user@10.0.0.1 2001:db8::1 > "$CASE/out"
    [ -L "$XDG_CONFIG_HOME/tmuxer/hosts" ]
    [ -L "$XDG_CONFIG_HOME/tmuxer/hosts-link" ]
    printf 'legacy\n' > "$CASE/expected"
    diff -u "$CASE/expected" "$CASE/linked directory/hosts"
    [ ! -e "$HOME/.config/tmuxer/hosts" ]
    local mode
    if ! mode=$(stat -c %a "$CASE/linked directory/hosts" 2>/dev/null); then
        mode=$(stat -f %Lp "$CASE/linked directory/hosts")
    fi
    [ "$mode" = 600 ]
    [ ! -e "$XDG_CONFIG_HOME/tmuxer/hosts.lock" ]
    assert_no_ssh
}
test_delete_io_errors() {
    mkdir -p "$HOME/.config/tmuxer/hosts"
    assert_status 2 run_tr hosts delete dev
    assert_contains "$CASE/err" 'cannot read allow list'
    rmdir "$HOME/.config/tmuxer/hosts"
    ln -s missing "$HOME/.config/tmuxer/hosts"
    assert_status 2 run_tr hosts delete dev
    assert_contains "$CASE/err" 'cannot read allow list'
    rm "$HOME/.config/tmuxer/hosts"
    printf 'dev\nstaging\n' > "$HOME/.config/tmuxer/hosts"
    cp "$HOME/.config/tmuxer/hosts" "$CASE/before"
    printf '#!/usr/bin/env bash\nexit 37\n' > "$CASE/bin/mv"
    chmod +x "$CASE/bin/mv"
    assert_status 2 run_tr hosts delete dev
    assert_contains "$CASE/err" 'cannot write allow list'
    [ ! -s "$CASE/out" ]
    diff -u "$CASE/before" "$HOME/.config/tmuxer/hosts"
    [ ! -e "$HOME/.config/tmuxer/hosts.lock" ]
    local temporary
    for temporary in "$HOME/.config/tmuxer"/.tmuxer-hosts.*; do
        [ ! -e "$temporary" ] || fail "leaked deletion temporary file: $temporary"
    done
    assert_no_ssh
}
test_delete_concurrent() {
    write_ssh_hosts first second keep added
    run_tr hosts register first second keep > /dev/null
    export MOCK_REAL_MV=$(command -v mv)
    cat > "$CASE/bin/mv" <<'MOCK'
#!/usr/bin/env bash
if [ ! -e "$MOCK_LOG/rename-release" ]; then
    touch "$MOCK_LOG/rename-ready"
    attempts=0
    while [ ! -e "$MOCK_LOG/rename-release" ]; do
        attempts=$((attempts + 1))
        [ "$attempts" -lt 500 ] || exit 70
        sleep 0.01
    done
fi
exec "$MOCK_REAL_MV" "$@"
MOCK
    chmod +x "$CASE/bin/mv"
    run_tr hosts delete first > "$CASE/first.out" &
    local first_pid=$! second_pid register_pid attempts=0
    while [ ! -e "$MOCK_LOG/rename-ready" ]; do
        attempts=$((attempts + 1))
        [ "$attempts" -lt 500 ] || fail 'deletion did not reach rename'
        sleep 0.01
    done
    # Force both operations to overlap the first deletion's read/replace.
    run_tr hosts register added > "$CASE/added.out" &
    register_pid=$!
    run_tr hosts delete second > "$CASE/second.out" &
    second_pid=$!
    sleep 0.1
    touch "$MOCK_LOG/rename-release"
    wait "$first_pid"
    wait "$second_pid"
    wait "$register_pid"
    run_tr hosts list > "$CASE/out"
    printf '%s\n' keep added > "$CASE/expected"
    diff -u "$CASE/expected" "$CASE/out"
    [ ! -e "$HOME/.config/tmuxer/hosts.lock" ]
    assert_no_ssh
}
test_delete_revokes_access() {
    write_ssh_hosts dev box
    run_tr hosts register dev box > /dev/null
    run_tr hosts delete dev > /dev/null
    assert_status 2 run_tr remote @dev ls
    assert_contains "$CASE/err" 'host is not registered: dev'
    assert_no_ssh
    write_row box 'work:1:0'
    export MOCK_PICK=$'box\twork\t1\tdetached'
    run_tty remote
    printf '%s\n' "$MOCK_PICK" > "$CASE/expected"
    diff -u "$CASE/expected" "$MOCK_LOG/fzf-input"
    assert_args "$MOCK_LOG/tmux.box" list-sessions -F '#{session_name}:#{session_windows}:#{session_attached}' attach -t '=work'
    [ ! -e "$MOCK_LOG/ssh.dev" ]
}
test_allowlist_picker() {
    mkdir -p "$HOME/.ssh/config.d"
    cat > "$HOME/.ssh/config" <<'CONFIG'
Host ignored dev *
Include config.d/*.conf
Match exec "touch SHOULD_NOT_RUN"
CONFIG
    printf 'Host included\n' > "$HOME/.ssh/config.d/one.conf"
    write_row local 'local session:1:0'
    export TR_HOSTS='dev ignored included'
    # SSH candidates and local sessions cannot populate an absent allow list.
    assert_status 1 run_tr remote
    assert_contains "$CASE/err" 'no registered hosts available'
    assert_no_ssh
    assert_no_local_tmux
    [ ! -e "$HOME/.config/tmuxer/hosts" ]
    run_tr hosts register dev > /dev/null
    printf 'outside-config\n' >> "$HOME/.config/tmuxer/hosts"
    clear_logs
    unset TR_HOSTS
    write_row dev 'work:1:0'
    write_row outside-config 'legacy:2:1'
    export MOCK_PICK=$'dev\twork\t1\tdetached'
    run_tty remote
    printf '%s\n' "$MOCK_PICK" $'outside-config\tlegacy\t2\tattached' > "$CASE/expected"
    diff -u "$CASE/expected" "$MOCK_LOG/fzf-input"
    assert_args "$MOCK_LOG/tmux.dev" list-sessions -F '#{session_name}:#{session_windows}:#{session_attached}' attach -t '=work'
    assert_args "$MOCK_LOG/tmux.outside-config" list-sessions -F '#{session_name}:#{session_windows}:#{session_attached}'
    [ ! -e "$MOCK_LOG/ssh.ignored" ]
    [ ! -e "$MOCK_LOG/ssh.included" ]
    assert_no_local_tmux
    [ ! -e "$CASE/SHOULD_NOT_RUN" ]
    assert_clean
}
test_hosts_filter() {
    write_ssh_hosts ignored alpha beta gamma excluded
    run_tr hosts register alpha beta gamma excluded > /dev/null
    write_row alpha 'one:1:0'
    write_row beta 'two:2:1'
    write_row gamma 'three:3:0'
    export TR_HOSTS=$'alpha beta alpha\ngamma\tunregistered star*' MOCK_PICK=$'beta\ttwo\t2\tattached'
    run_tty remote
    printf '%s\n' $'alpha\tone\t1\tdetached' "$MOCK_PICK" $'gamma\tthree\t3\tdetached' > "$CASE/expected"
    diff -u "$CASE/expected" "$MOCK_LOG/fzf-input"
    assert_args "$MOCK_LOG/tmux.beta" list-sessions -F '#{session_name}:#{session_windows}:#{session_attached}' attach -t '=two'
    assert_args "$MOCK_LOG/tmux.alpha" list-sessions -F '#{session_name}:#{session_windows}:#{session_attached}'
    assert_args "$MOCK_LOG/tmux.gamma" list-sessions -F '#{session_name}:#{session_windows}:#{session_attached}'
    [ ! -e "$MOCK_LOG/ssh.excluded" ]
    clear_logs
    export TR_HOSTS=
    assert_status 1 run_tr remote
    assert_no_ssh
    assert_no_local_tmux
    # Explicit references may still use any registered host.
    run_tr remote @excluded ls
    assert_args "$MOCK_LOG/tmux.excluded" ls
}
test_unregistered_remote() {
    printf 'Host box\n' > "$HOME/.ssh/config"
    export TR_HOSTS=box
    assert_status 2 run_tr remote @box ls
    assert_contains "$CASE/err" 'run: tx hosts register box'
    assert_status 2 run_tr remote @box attach
    assert_status 2 run_tr remote @box
    assert_no_ssh
    run_tr hosts register box > /dev/null
    run_tr remote @box ls
    assert_args "$MOCK_LOG/tmux.box" ls
    : > "$HOME/.config/tmuxer/hosts"
    clear_logs
    assert_status 2 run_tr remote @box ls
    assert_no_ssh
    assert_status 0 run_tr ls
}

selector_fixture() {
    write_ssh_hosts box
    run_tr hosts register box > /dev/null
    export TR_HOSTS=box MOCK_EXPECT_CLEAN=1
    SESSION="  odd ' \$;[] name  "
    write_row local "$SESSION:1:0"
    write_row box "$SESSION:2:1"
}
test_select_local() {
    selector_fixture
    export MOCK_PICK=$'[local]\t'"$SESSION"$'\t1\tdetached'
    run_tr
    assert_args "$MOCK_LOG/tmux.local" list-sessions -F '#{session_name}:#{session_windows}:#{session_attached}' attach -t "=$SESSION"
    assert_contains "$MOCK_LOG/fzf" '--preview-window'
    printf '%s\n' "$MOCK_PICK" > "$CASE/expected"
    diff -u "$CASE/expected" "$MOCK_LOG/fzf-input"
    assert_no_ssh
    assert_clean
}
test_select_nested() {
    selector_fixture
    export TMUX='fake,123,0' MOCK_PICK=$'[local]\t'"$SESSION"$'\t1\tdetached'
    run_tr
    assert_args "$MOCK_LOG/tmux.local" list-sessions -F '#{session_name}:#{session_windows}:#{session_attached}' switch-client -t "=$SESSION"
    assert_no_ssh
    assert_clean
}
test_select_host() {
    unset TR_HOSTS
    write_ssh_hosts box other empty dead password barrier-a barrier-b
    run_tr hosts register box other empty dead password barrier-a barrier-b > /dev/null
    write_row local 'local-only:1:0'
    write_row box $'work:2:1\nsecond:3:0'
    write_row other 'work:1:0'
    write_row barrier-a 'parallel-a:1:0'
    write_row barrier-b 'parallel-b:1:0'
    export MOCK_PICK=$'box\twork\t2\tattached' MOCK_BARRIER=1 TMUX='fake,123,0' MOCK_EXPECT_CLEAN=1
    run_tty remote
    printf '%s\n' "$MOCK_PICK" $'box\tsecond\t3\tdetached' $'other\twork\t1\tdetached' \
        $'barrier-a\tparallel-a\t1\tdetached' $'barrier-b\tparallel-b\t1\tdetached' > "$CASE/expected"
    diff -u "$CASE/expected" "$MOCK_LOG/fzf-input"
    assert_args "$MOCK_LOG/tmux.box" list-sessions -F '#{session_name}:#{session_windows}:#{session_attached}' attach -t '=work'
    assert_args "$MOCK_LOG/tmux.other" list-sessions -F '#{session_name}:#{session_windows}:#{session_attached}'
    assert_args "$MOCK_LOG/tmux.empty" list-sessions -F '#{session_name}:#{session_windows}:#{session_attached}'
    assert_contains "$MOCK_LOG/ssh.box" 'BatchMode=yes'
    assert_contains "$MOCK_LOG/ssh.dead" 'ConnectTimeout=3'
    assert_contains "$MOCK_LOG/ssh.password" 'ConnectionAttempts=1'
    assert_contains "$MOCK_LOG/ssh.box" '-t'
    [ -f "$MOCK_LOG/ready.barrier-a" ] && [ -f "$MOCK_LOG/ready.barrier-b" ]
    assert_no_local_tmux
    assert_clean
}
test_select_specific_host() {
    selector_fixture
    write_ssh_hosts box other
    run_tr hosts register other > /dev/null
    # Explicit host selection bypasses TR_HOSTS and never touches another server.
    export TR_HOSTS= TMUX='fake,123,0' MOCK_PICK=$'box\t'"$SESSION"$'\t2\tattached'
    run_tty remote @box
    printf '%s\n' "$MOCK_PICK" > "$CASE/expected"
    diff -u "$CASE/expected" "$MOCK_LOG/fzf-input"
    assert_args "$MOCK_LOG/tmux.box" list-sessions -F '#{session_name}:#{session_windows}:#{session_attached}' attach -t "=$SESSION"
    local quote_expected_scan="'tmux' 'list-sessions' '-F' '#{session_name}:#{session_windows}:#{session_attached}'"
    local quoted_session=${SESSION//\'/\'\\\'\'}
    assert_args "$MOCK_LOG/ssh.box" -T -- box "$quote_expected_scan" -t -- box "'tmux' 'attach' '-t' '=$quoted_session'"
    [ ! -e "$MOCK_LOG/ssh.other" ]
    assert_no_local_tmux
    assert_clean
}
test_select_revoked() {
    write_ssh_hosts box
    run_tr hosts register box > /dev/null
    write_row box 'work:1:0'
    export MOCK_REVOKE_REGISTRATION=1 MOCK_PICK=$'box\twork\t1\tdetached'
    assert_status 2 run_tty remote @box
    assert_contains "$CASE/tty-output" 'host is not registered: box'
    assert_args "$MOCK_LOG/tmux.box" list-sessions -F '#{session_name}:#{session_windows}:#{session_attached}'
    assert_no_local_tmux
    assert_clean
}
test_select_tmux_args() {
    write_ssh_hosts box ls
    run_tr hosts register box ls > /dev/null
    # Any remote command, including the old wrapper commands, requires @host.
    local command
    for command in ls box exec sessions select register delete help --help; do
        assert_status 2 run_tr remote "$command"
        assert_contains "$CASE/err" 'require a server reference'
    done
    assert_status 2 run_tty remote new-session -s work
    assert_status 2 run_tty remote -L socket ls
    assert_no_ssh
    assert_no_local_tmux
    [ ! -e "$MOCK_LOG/fzf" ]
    run_tty remote @box new-session -s '@work'
    assert_args "$MOCK_LOG/tmux.box" new-session -s '@work'
    assert_contains "$MOCK_LOG/ssh.box" '-t'
    clear_logs
    run_tty remote @box -vLsocket -S '/tmp/a b' -- send-keys -H '@target' '' 'a"b' '$HOME; $(touch nope)' $'two\nlines'
    assert_args "$MOCK_LOG/tmux.box" -vLsocket -S '/tmp/a b' -- send-keys -H '@target' '' 'a"b' '$HOME; $(touch nope)' $'two\nlines'
    assert_contains "$MOCK_LOG/ssh.box" '-T'
    [ ! -e "$CASE/nope" ]
    clear_logs
    # Arguments after @host are always forwarded, including former subcommands.
    run_tty remote @box box ls
    assert_args "$MOCK_LOG/tmux.box" box ls
    clear_logs
    run_tty remote @box exec box ls
    assert_args "$MOCK_LOG/tmux.box" exec box ls
    clear_logs
    run_tty remote @box sessions
    assert_args "$MOCK_LOG/tmux.box" sessions
    assert_no_local_tmux
    [ ! -e "$MOCK_LOG/fzf" ]
}
test_select_noninteractive() {
    write_ssh_hosts box
    run_tr hosts register box > /dev/null
    assert_status 2 run_tr remote
    assert_contains "$CASE/err" 'requires an interactive terminal'
    assert_contains "$CASE/err" 'tx remote @host ls'
    assert_status 2 run_tr remote @box
    [ ! -e "$MOCK_LOG/fzf" ]
    assert_no_ssh
    run_tr remote @box ls
    assert_args "$MOCK_LOG/tmux.box" ls
}
test_select_invalid() {
    write_ssh_hosts box excluded
    run_tr hosts register box excluded > /dev/null
    write_row box 'work:1:0'
    export TR_HOSTS=box MOCK_PICK=$'box\twork\t1\tdetached'
    local forced
    for forced in $'excluded\twork\t1\tdetached' $'box\tinvented\t1\tdetached' $'[local]\twork\t1\tdetached' $'box\twork\t1\tdetached\nbox\twork\t1\tdetached'; do
        clear_logs
        export MOCK_FORCE_PICK=$forced
        assert_status 2 run_tty remote
        assert_contains "$CASE/tty-output" 'fzf returned an invalid session'
        assert_args "$MOCK_LOG/tmux.box" list-sessions -F '#{session_name}:#{session_windows}:#{session_attached}'
        [ ! -e "$MOCK_LOG/ssh.excluded" ]
        assert_no_local_tmux
        assert_clean
    done
    unset MOCK_FORCE_PICK
    export MOCK_EMPTY_PICK=1
    clear_logs
    assert_status 1 run_tty remote
    assert_args "$MOCK_LOG/tmux.box" list-sessions -F '#{session_name}:#{session_windows}:#{session_attached}'
}
test_select_stdin() {
    write_ssh_hosts box
    run_tr hosts register box > /dev/null
    export MOCK_READ_STDIN=1 TTY_STDIN="$CASE/command input"
    printf '%s\n' 'stdin for tmux' '$HOME; $(touch nope)' > "$TTY_STDIN"
    run_tty remote @box load-buffer -
    assert_args "$MOCK_LOG/tmux.box" load-buffer -
    diff -u "$TTY_STDIN" "$MOCK_LOG/stdin.box"
    assert_contains "$MOCK_LOG/ssh.box" '-T'
    assert_no_local_tmux
    [ ! -e "$MOCK_LOG/fzf" ]
}
test_remote_user_reference() {
    write_ssh_hosts user@2001:db8::1 @box
    run_tr hosts register user@2001:db8::1 @box > /dev/null
    run_tr remote @user@2001:db8::1 ls
    assert_args "$MOCK_LOG/tmux.user@2001:db8::1" ls
    run_tr remote @@box send-keys '@another'
    assert_args "$MOCK_LOG/tmux.@box" send-keys '@another'
    [ ! -e "$MOCK_LOG/fzf" ]
}
test_preview_local() {
    selector_fixture
    export MOCK_RUN_PREVIEW=1 MOCK_PICK=$'[local]\t'"$SESSION"$'\t1\tdetached'
    run_tr
    assert_args "$MOCK_LOG/tmux.local" list-sessions -F '#{session_name}:#{session_windows}:#{session_attached}' capture-pane -p -t "=$SESSION:" -S -100 attach -t "=$SESSION"
    assert_contains "$MOCK_LOG/preview-output" 'mock pane contents'
    assert_no_ssh
    assert_clean
}
test_preview_remote() {
    selector_fixture
    export MOCK_RUN_PREVIEW=1 MOCK_PICK=$'box\t'"$SESSION"$'\t2\tattached'
    run_tty remote
    assert_args "$MOCK_LOG/tmux.box" list-sessions -F '#{session_name}:#{session_windows}:#{session_attached}' capture-pane -p -t "=$SESSION:" -S -100 attach -t "=$SESSION"
    assert_contains "$MOCK_LOG/preview-output" 'mock pane contents'
    assert_no_local_tmux
    assert_clean
    clear_logs
    run_tty remote @box
    assert_args "$MOCK_LOG/tmux.box" list-sessions -F '#{session_name}:#{session_windows}:#{session_attached}' capture-pane -p -t "=$SESSION:" -S -100 attach -t "=$SESSION"
    assert_contains "$MOCK_LOG/preview-output" 'mock pane contents'
    assert_no_local_tmux
    assert_clean
    clear_logs
    export MOCK_REVOKE_REGISTRATION=1
    assert_status 2 run_tty remote @box
    assert_args "$MOCK_LOG/tmux.box" list-sessions -F '#{session_name}:#{session_windows}:#{session_attached}'
    assert_clean
}
test_remote_empty_errors() {
    write_ssh_hosts box empty dead password
    run_tr hosts register box empty dead password > /dev/null
    assert_status 1 run_tty remote
    assert_contains "$CASE/tty-output" 'no available sessions found'
    assert_no_local_tmux
    [ ! -e "$MOCK_LOG/fzf" ]
    assert_clean
    clear_logs
    assert_status 1 run_tty remote @empty
    assert_contains "$CASE/tty-output" 'no available sessions found'
    assert_args "$MOCK_LOG/tmux.empty" list-sessions -F '#{session_name}:#{session_windows}:#{session_attached}'
    assert_clean
    clear_logs
    assert_status 255 run_tty remote @dead
    [ ! -e "$MOCK_LOG/fzf" ]
    assert_clean
    clear_logs
    export MOCK_TMUX_STATUS=37
    assert_status 37 run_tty remote @box
    assert_args "$MOCK_LOG/tmux.box" list-sessions -F '#{session_name}:#{session_windows}:#{session_attached}'
    assert_clean
}

test_cancel_empty_missing_fzf() {
    assert_status 1 run_tr
    assert_contains "$CASE/err" 'no available sessions found'
    [ ! -e "$MOCK_LOG/fzf" ]
    assert_no_ssh
    assert_clean
    write_row local 'one:1:0'
    assert_status 1 run_tr remote
    assert_contains "$CASE/err" 'no registered hosts available'
    [ ! -e "$MOCK_LOG/fzf" ]
    assert_no_ssh
    clear_logs
    mkdir -p "$HOME/.config/tmuxer"
    : > "$HOME/.config/tmuxer/hosts"
    assert_status 1 run_tr remote
    assert_no_local_tmux
    assert_no_ssh
    write_ssh_hosts box
    run_tr hosts register box > /dev/null
    write_row box 'remote-one:1:0'
    export TR_HOSTS=
    assert_status 1 run_tr remote
    assert_no_ssh
    unset TR_HOSTS
    export MOCK_CANCEL=1
    assert_status 130 run_tr
    clear_logs
    assert_status 130 run_tty remote
    assert_args "$MOCK_LOG/tmux.box" list-sessions -F '#{session_name}:#{session_windows}:#{session_attached}'
    assert_no_local_tmux
    assert_clean
    clear_logs
    rm "$CASE/bin/fzf"
    minimal_path
    assert_status 2 run_tr
    assert_contains "$CASE/err" 'requires fzf'
    assert_contains "$CASE/err" 'tx ls'
    assert_status 2 run_tty remote
    assert_contains "$CASE/tty-output" 'requires fzf'
    assert_contains "$CASE/tty-output" 'tx remote @host'
    assert_no_ssh
    assert_status 0 run_tr remote @box ls
    assert_status 0 run_tr ls
    assert_clean
}
test_script_path_spaces() {
    mkdir "$CASE/a directory's"
    cp "$TR" "$CASE/a directory's/tx"
    TR="$CASE/a directory's/tx"
    test_preview_local
    clear_logs
    export MOCK_RUN_PREVIEW=0
    test_select_host
}
test_install() {
    NAME=tm PREFIX="$CASE/prefix space" "$TEST_BASH" "$TEST_ROOT/install.sh" > "$CASE/out"
    [ -x "$CASE/prefix space/bin/tm" ]
    cmp "$TR" "$CASE/prefix space/bin/tm"
    cmp "$TEST_ROOT/completions/tx.zsh" "$CASE/prefix space/share/tmuxer/tx.zsh"
    "$CASE/prefix space/bin/tm" help > "$CASE/out"
    assert_contains "$CASE/out" 'Usage: tm '
    assert_contains "$CASE/out" 'tm hosts register host'
    assert_contains "$CASE/out" 'tm hosts delete host'
    assert_contains "$CASE/out" 'tm hosts candidates'
    write_ssh_hosts configured custom-host registered
    "$CASE/prefix space/bin/tm" hosts candidates > "$CASE/out"
    assert_contains "$CASE/out" 'configured'
    "$CASE/prefix space/bin/tm" hosts register custom-host > "$CASE/out"
    "$CASE/prefix space/bin/tm" hosts list > "$CASE/out"
    assert_contains "$CASE/out" 'custom-host'
    "$CASE/prefix space/bin/tm" remote @custom-host ls
    assert_args "$MOCK_LOG/tmux.custom-host" ls
    assert_status 2 "$CASE/prefix space/bin/tm" remote @unregistered ls
    assert_contains "$CASE/err" 'run: tm hosts register unregistered'
    "$CASE/prefix space/bin/tm" hosts delete custom-host > "$CASE/out"
    assert_contains "$CASE/out" 'Deleted: custom-host'
    "$CASE/prefix space/bin/tm" hosts list > "$CASE/out"
    [ ! -s "$CASE/out" ]
    "$TEST_BASH" "$TEST_ROOT/install.sh" > "$CASE/out"
    [ -x "$HOME/.local/bin/tx" ]
    [ ! -e "$HOME/.local/bin/tr" ]
    cmp "$TR" "$HOME/.local/bin/tx"
    cmp "$TEST_ROOT/completions/tx.zsh" "$HOME/.local/share/tmuxer/tx.zsh"
    PATH="$HOME/.local/bin:$CASE/bin:/usr/bin:/bin"
    export PATH
    tx help > "$CASE/out"
    assert_contains "$CASE/out" 'Usage: tx '
    assert_contains "$CASE/out" 'tx hosts register host'
    tx hosts register registered > "$CASE/out"
    tx hosts list > "$CASE/out"
    assert_contains "$CASE/out" 'registered'
    tx remote @registered ls
    assert_args "$MOCK_LOG/tmux.registered" ls
    assert_status 2 tx remote @unregistered ls
    assert_contains "$CASE/err" 'run: tx hosts register unregistered'
    assert_status 2 tx remote @
    assert_contains "$CASE/err" 'tx: invalid host'
    tx ls
    assert_args "$MOCK_LOG/tmux.local" ls
    # NVM uses this conversion during shell startup. It must reach system tr.
    [ "$(printf t | command tr t '\t')" = $'\t' ]
    assert_status 2 env NAME='../bad' PREFIX="$CASE/prefix" "$TEST_BASH" "$TEST_ROOT/install.sh"
}
test_zsh_completion() {
    if ! command -v zsh >/dev/null 2>&1; then
        printf 'SKIP Zsh completion: zsh is not installed\n'
        return
    fi
    write_ssh_hosts configured second registered user@2001:db8::1
    run_tr hosts register registered user@2001:db8::1 > /dev/null
    touch "$CASE/canary-file"
    mkdir "$TMPDIR/socket-directory"
    export TR_HOSTS=
    # Test both the default command and a custom name/prefix with spaces.
    "$TEST_BASH" "$TEST_ROOT/install.sh" > "$CASE/out"
    PATH="$HOME/.local/bin:$PATH" zsh -f "$TEST_ROOT/tests/completion.zsh" "$HOME/.local/share/tmuxer/tx.zsh" tx
    NAME=tm PREFIX="$CASE/prefix space" "$TEST_BASH" "$TEST_ROOT/install.sh" > "$CASE/out"
    PATH="$CASE/prefix space/bin:$PATH" zsh -f "$TEST_ROOT/tests/completion.zsh" "$CASE/prefix space/share/tmuxer/tx.zsh" tm
    assert_no_ssh
    [ ! -e "$MOCK_LOG/fzf" ]
}
test_real_tmux() {
    [ -n "$REAL_TMUX" ] || fail 'real tmux is required'
    REAL_DIR=$(mktemp -d /tmp/tr-real.XXXXXXXX)
    export PATH=$ORIGINAL_PATH TR_HOSTS= TMUX_TMPDIR=$REAL_DIR
    trap '"$REAL_TMUX" kill-server 2>/dev/null || :; "$REAL_TMUX" -L tr-test kill-server 2>/dev/null || :; "$REAL_TMUX" -S "$REAL_DIR/custom socket" kill-server 2>/dev/null || :; rm -rf "$CASE" "$REAL_DIR"' EXIT
    local session="test space's \$;[]" output found=0 i
    run_tr -f /dev/null new-session -d -s "$session" 'exec /bin/sh'
    run_tr ls > "$CASE/out"
    assert_contains "$CASE/out" "$session"
    run_tr send-keys -t "=$session:" "printf '%s\\n' 'TR_REAL_OK'" Enter
    for ((i=0; i<100; i++)); do
        output=$(run_tr capture-pane -p -t "=$session:")
        case "$output" in *$'\nTR_REAL_OK\n'*) found=1; break ;; esac
        sleep 0.05
    done
    [ "$found" -eq 1 ] || fail 'real pane did not print marker'
    # Exercise actual local discovery and preview, then cancel before attaching.
    mkdir "$REAL_DIR/bin"
    cp "$TEST_ROOT/tests/mocks/fzf" "$REAL_DIR/bin/fzf"
    export PATH="$REAL_DIR/bin:$ORIGINAL_PATH" MOCK_PICK=$'[local]\t'"$session"$'\t1\tdetached'
    export MOCK_RUN_PREVIEW=1 MOCK_CANCEL_AFTER_PREVIEW=1
    assert_status 130 run_tr
    assert_contains "$MOCK_LOG/fzf-input" "$MOCK_PICK"
    assert_contains "$MOCK_LOG/preview-output" 'TR_REAL_OK'
    assert_clean
    assert_status 1 run_tr remote
    assert_contains "$CASE/err" 'no registered hosts available'
    run_tr kill-session -t "=$session"
    assert_status 1 run_tr ls
    run_tr -L tr-test -f /dev/null new-session -d -s custom
    run_tr -L tr-test ls > "$CASE/out"
    assert_contains "$CASE/out" custom
    run_tr -L tr-test kill-session -t '=custom'
    run_tr -S "$REAL_DIR/custom socket" -f /dev/null new-session -d -s custom
    run_tr -S "$REAL_DIR/custom socket" ls > "$CASE/out"
    assert_contains "$CASE/out" custom
    run_tr -S "$REAL_DIR/custom socket" kill-session -t '=custom'
}

if [ "${1-}" = --case ]; then
    CASE=$(mktemp -d "$WORK/case.XXXXXXXX")
    trap 'rm -rf "$CASE"' EXIT
    mkdir -p "$CASE/bin" "$CASE/home/.ssh" "$CASE/tmp" "$CASE/log" "$CASE/rows"
    cp "$TEST_ROOT/tests/mocks/ssh" "$TEST_ROOT/tests/mocks/tmux" "$TEST_ROOT/tests/mocks/fzf" "$CASE/bin/"
    chmod +x "$CASE/bin/ssh" "$CASE/bin/tmux" "$CASE/bin/fzf"
    export HOME=$CASE/home TMPDIR=$CASE/tmp MOCK_LOG=$CASE/log MOCK_ROWS=$CASE/rows PATH=$CASE/bin:$ORIGINAL_PATH
    unset XDG_CONFIG_HOME TMUX TMUX_TMPDIR TR_HOSTS TR_INTERNAL_PREVIEW MOCK_HOST MOCK_TMUX_STATUS MOCK_CANCEL MOCK_CANCEL_AFTER_PREVIEW MOCK_PICK MOCK_RUN_PREVIEW MOCK_BARRIER MOCK_EXPECT_CLEAN MOCK_REVOKE_REGISTRATION MOCK_FORCE_PICK MOCK_EMPTY_PICK MOCK_READ_STDIN TTY_STDIN
    cd "$CASE"
    "test_$2"
    exit 0
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/tr-tests.XXXXXXXX")
trap 'rm -rf "$WORK"' EXIT
export WORK TEST_BASH ORIGINAL_PATH REAL_TMUX
tests='local_forward local_default local_namespace remote_quotes exit_status global_options non_tty tty_attach tty_other errors_help remote_reference_names remote_user_reference hosts_list candidates_empty candidates_aliases candidates_includes candidates_errors register register_concurrent register_invalid register_candidates register_candidates_empty register_candidates_includes register_candidates_errors register_legacy_hosts register_config_path register_io_errors delete delete_invalid delete_config_path delete_io_errors delete_concurrent delete_revokes_access allowlist_picker hosts_filter unregistered_remote select_local select_nested select_host select_specific_host select_revoked select_tmux_args select_noninteractive select_invalid select_stdin preview_local preview_remote remote_empty_errors cancel_empty_missing_fzf script_path_spaces install zsh_completion real_tmux'
passed=0
failed=0
for test in $tests; do
    if "$TEST_BASH" "$0" --case "$test" > "$WORK/output" 2>&1 </dev/null; then
        printf 'PASS %s\n' "$test"
        passed=$((passed + 1))
    else
        printf 'FAIL %s\n' "$test"
        cat "$WORK/output"
        failed=$((failed + 1))
    fi
done
printf '\n%d passed, %d failed (%s)\n' "$passed" "$failed" "$TEST_BASH"
printf 'SSH, remote tmux, and fzf are mocked; PTY tests use script(1), and real_tmux uses local tmux.\n'
[ "$failed" -eq 0 ]
