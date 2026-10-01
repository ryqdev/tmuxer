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
assert_status() {
    local wanted=$1 actual=0
    shift
    "$@" > "$CASE/out" 2> "$CASE/err" || actual=$?
    [ "$actual" -eq "$wanted" ] || fail "exit $actual, expected $wanted: $*"
}
clear_logs() { rm -f "$MOCK_LOG"/*; }
write_row() { printf '%s\n' "$2" > "$MOCK_ROWS/$1"; }
run_tr() { "$TEST_BASH" "$TR" "$@"; }
minimal_path() {
    local tool
    for tool in bash awk sed mktemp rm mkdir tail; do ln -s "$(command -v "$tool")" "$CASE/bin/$tool"; done
    PATH=$CASE/bin
    export PATH
}
run_tty() {
    command -v script >/dev/null 2>&1 || fail 'PTY tests require script(1)'
    printf 'exec ' > "$CASE/tty-command"
    printf '%q ' "$TEST_BASH" "$TR" "$@" >> "$CASE/tty-command"
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
    # Local commands must not read the allow list, discover hosts, or need fzf.
    mkdir -p "$HOME/.config/tmuxer"
    printf 'invalid host\n' > "$HOME/.config/tmuxer/hosts"
    export TR_HOSTS=box TR_INTERNAL_PREVIEW=1
    rm "$CASE/bin/fzf" "$CASE/bin/ssh"
    run_tr
    assert_args "$MOCK_LOG/tmux.local"
    [ ! -e "$MOCK_LOG/fzf" ]
    clear_logs
    run_tr -L 'local socket' ls
    assert_args "$MOCK_LOG/tmux.local" -L 'local socket' ls
    export MOCK_TMUX_STATUS=37
    assert_status 37 run_tr
    assert_no_ssh
}
test_local_namespace() {
    # The old wrapper commands and flags are now passed straight to local tmux.
    run_tr register box
    assert_args "$MOCK_LOG/tmux.local" register box
    [ ! -e "$HOME/.config/tmuxer/hosts" ]
    clear_logs
    run_tr -H box ls
    assert_args "$MOCK_LOG/tmux.local" -H box ls
    clear_logs
    run_tr -L remote -- ls
    assert_args "$MOCK_LOG/tmux.local" -L remote -- ls
    assert_no_ssh
}
test_remote_quotes() {
    run_tr remote register box > /dev/null
    run_tr remote -H box send-keys 'python x.py --a '\''b c'\''' '' "''''" 'a"b' '$HOME; $(touch nope)' $'two\nlines' '\path' </dev/null
    assert_args "$MOCK_LOG/tmux.box" send-keys 'python x.py --a '\''b c'\''' '' "''''" 'a"b' '$HOME; $(touch nope)' $'two\nlines' '\path'
    assert_contains "$MOCK_LOG/ssh.box" '-T'
    [ ! -e "$CASE/nope" ]
}
test_exit_status() {
    run_tr remote register box > /dev/null
    export MOCK_TMUX_STATUS=37
    assert_status 37 run_tr ls
    assert_status 37 run_tr remote -H box ls
}
test_global_options() {
    run_tr remote register box > /dev/null
    run_tr -L 'local socket' ls
    assert_args "$MOCK_LOG/tmux.local" -L 'local socket' ls
    run_tr remote -S '/tmp/a b' -H box -f 'my config' -T 'flags' -c 'shell command' -v capture-pane -p
    assert_args "$MOCK_LOG/tmux.box" -S '/tmp/a b' -f 'my config' -T flags -c 'shell command' -v capture-pane -p
    clear_logs
    run_tr remote -H box -L -H ls
    assert_args "$MOCK_LOG/tmux.box" -L -H ls
    clear_logs
    run_tr remote -H box -- send-keys -H
    assert_args "$MOCK_LOG/tmux.box" -- send-keys -H
}
test_non_tty() {
    run_tr remote register box > /dev/null
    local command
    for command in attach attach-session a at new new-session ls capture-pane send-keys ''; do
        clear_logs
        if [ -n "$command" ]; then run_tr remote -H box "$command" </dev/null; else run_tr remote -H box </dev/null; fi
        assert_contains "$MOCK_LOG/ssh.box" '-T'
    done
    run_tr remote -H box capture-pane -p | awk '{print}' > "$CASE/piped"
    assert_contains "$CASE/piped" 'mock pane contents'
}
test_tty_attach() {
    run_tr remote register box > /dev/null
    local command
    for command in attach attach-session a at new new-session ''; do
        clear_logs
        if [ -n "$command" ]; then run_tty remote -H box -L 'socket space' "$command";
        else run_tty remote -H box -S '/tmp/my socket'; fi
        assert_contains "$MOCK_LOG/ssh.box" '-t'
    done
    clear_logs
    run_tty remote -H box -vLsocket -S '/tmp/my socket' -f attach -T new -c a at
    assert_contains "$MOCK_LOG/ssh.box" '-t'
}
test_tty_other() {
    run_tr remote register box > /dev/null
    local command
    for command in ls capture-pane send-keys; do
        clear_logs
        run_tty remote -H box -L attach -S new "$command"
        assert_contains "$MOCK_LOG/ssh.box" '-T'
    done
}
test_errors_help() {
    assert_status 2 run_tr remote -H
    assert_contains "$CASE/err" '-H requires a host argument'
    assert_status 2 run_tr remote -H ''
    assert_status 2 run_tr remote -H --help
    assert_status 2 run_tr remote -H all
    assert_status 2 run_tr remote -H all new
    assert_status 2 run_tr remote -H all list-sessions
    assert_status 2 run_tr remote -H all ls extra
    assert_status 2 run_tr remote list extra
    assert_contains "$CASE/err" 'remote list does not accept arguments'
    assert_status 2 run_tr remote ls
    assert_contains "$CASE/err" 'remote tmux commands require -H host'
    assert_status 2 run_tr remote typo
    assert_status 0 run_tr --help
    assert_contains "$CASE/out" 'tx remote register host'
    assert_contains "$CASE/out" 'tx remote list'
    assert_status 0 run_tr remote --help
    assert_contains "$CASE/out" 'TR_HOSTS'
    [ ! -e "$MOCK_LOG/tmux.local" ]
    [ ! -e "$MOCK_LOG/ssh.all" ]
}
test_remote_list() {
    # Missing or empty lists produce no output and do not create any files.
    run_tr remote list > "$CASE/out"
    [ ! -s "$CASE/out" ]
    [ ! -e "$HOME/.config/tmuxer/hosts" ]
    run_tr remote register dev box > /dev/null
    printf '# hosts\ndev\n\nbox\ndev\nuser@10.0.0.1' > "$HOME/.config/tmuxer/hosts"
    export TR_HOSTS=dev
    # Host listing is offline and is not filtered by session discovery settings.
    rm "$CASE/bin/tmux" "$CASE/bin/ssh" "$CASE/bin/fzf"
    minimal_path
    run_tr remote list > "$CASE/out"
    printf '%s\n' dev box user@10.0.0.1 > "$CASE/expected"
    /usr/bin/diff -u "$CASE/expected" "$CASE/out"
    assert_no_ssh
    [ ! -e "$MOCK_LOG/tmux.local" ]
    [ ! -e "$MOCK_LOG/fzf" ]
    : > "$HOME/.config/tmuxer/hosts"
    run_tr remote list > "$CASE/out"
    [ ! -s "$CASE/out" ]
}
test_register() {
    local mode
    run_tr remote register dev box dev user@10.0.0.1 2001:db8::1 > "$CASE/out"
    assert_contains "$CASE/out" 'Registered: dev'
    run_tr remote register box staging > "$CASE/out"
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
    run_tr remote register offline > "$CASE/out"
    assert_contains "$HOME/.config/tmuxer/hosts" offline
}
test_register_concurrent() {
    local i pid
    local -a pids
    pids=()
    run_tr remote register existing > /dev/null
    for ((i=0; i<8; i++)); do
        run_tr remote register "server-$i" > "$CASE/register-$i.out" &
        pids[${#pids[@]}]=$!
    done
    for pid in "${pids[@]}"; do wait "$pid"; done
    assert_no_ssh
    run_tr remote -H all ls > "$CASE/out"
    [ -f "$MOCK_LOG/ssh.existing" ]
    for ((i=0; i<8; i++)); do
        [ -f "$MOCK_LOG/ssh.server-$i" ] || fail "lost registration: server-$i"
    done
    local files=("$MOCK_LOG"/ssh.*)
    [ "${#files[@]}" -eq 9 ]
    assert_clean
}
test_register_invalid() {
    local host
    assert_status 2 run_tr remote register
    assert_contains "$CASE/err" 'register requires at least one host'
    for host in '' -option all '[local]' 'two hosts' $'two\nhosts' $'two\thosts' 'wild*' 'wild?' '!negative' '[pattern]' '$(touch nope)' 'host;touch nope'; do
        assert_status 2 run_tr remote register valid "$host"
        assert_contains "$CASE/err" 'invalid host'
        [ ! -e "$HOME/.config/tmuxer/hosts" ]
    done
    [ ! -e "$CASE/nope" ]
    assert_no_ssh
    [ ! -e "$MOCK_LOG/tmux.local" ]
    # An invalid addition must leave an existing allow list unchanged.
    run_tr remote register dev > /dev/null
    assert_status 2 run_tr remote register staging 'bad host'
    printf 'dev\n' > "$CASE/expected"
    diff -u "$CASE/expected" "$HOME/.config/tmuxer/hosts"
}
test_register_config_path() {
    export XDG_CONFIG_HOME="$CASE/config directory's"
    run_tr remote register box > /dev/null
    [ -f "$XDG_CONFIG_HOME/tmuxer/hosts" ]
    [ ! -e "$HOME/.config/tmuxer/hosts" ]
    # Comments, duplicates, empty lines and an unterminated final line are safe.
    printf '# registered hosts\nbox\n\nbox\ndev' > "$XDG_CONFIG_HOME/tmuxer/hosts"
    run_tr remote register staging > /dev/null
    printf '# registered hosts\nbox\n\nbox\ndev\nstaging\n' > "$CASE/expected"
    diff -u "$CASE/expected" "$XDG_CONFIG_HOME/tmuxer/hosts"
    run_tr remote list > "$CASE/out"
    printf '%s\n' box dev staging > "$CASE/expected"
    diff -u "$CASE/expected" "$CASE/out"
    run_tr remote -H all ls > "$CASE/out"
    local host
    for host in box dev staging; do [ -f "$MOCK_LOG/ssh.$host" ]; done
    local files=("$MOCK_LOG"/ssh.*)
    [ "${#files[@]}" -eq 3 ] || fail 'duplicate scan of registered host'
    clear_logs
    run_tr remote -H dev ls
    [ -f "$MOCK_LOG/ssh.dev" ]
    assert_clean
}
test_register_io_errors() {
    mkdir -p "$HOME/.config/tmuxer/hosts"
    assert_status 2 run_tr remote register box
    assert_contains "$CASE/err" 'cannot read allow list'
    assert_status 2 run_tr remote -H all ls
    assert_contains "$CASE/err" 'cannot read allow list'
    assert_status 2 run_tr remote list
    assert_contains "$CASE/err" 'cannot read allow list'
    rm -rf "$HOME/.config/tmuxer"
    printf 'not a directory\n' > "$HOME/.config/tmuxer"
    assert_status 2 run_tr remote register box
    assert_contains "$CASE/err" 'cannot write allow list'
    rm "$HOME/.config/tmuxer"
    mkdir "$HOME/.config/tmuxer"
    printf 'valid\nbad host\n' > "$HOME/.config/tmuxer/hosts"
    assert_status 2 run_tr remote -H all ls
    assert_contains "$CASE/err" 'invalid host'
    assert_status 2 run_tr remote list
    assert_contains "$CASE/err" 'invalid host'
    assert_no_ssh
    [ ! -e "$MOCK_LOG/tmux.local" ]
}
test_allowlist_discovery() {
    mkdir -p "$HOME/.ssh/config.d"
    cat > "$HOME/.ssh/config" <<'CONFIG'
Host ignored dev *
Include config.d/*.conf
Match exec "touch SHOULD_NOT_RUN"
CONFIG
    printf 'Host included\n' > "$HOME/.ssh/config.d/one.conf"
    write_row local 'local session:1:0'
    write_row dev 'remote session:2:0'
    write_row ignored 'hidden session:1:0'
    write_row included 'hidden session:1:0'
    export TR_HOSTS='dev ignored included'
    # A missing allow list means local sessions only, even with SSH config/TR_HOSTS.
    run_tr remote -H all ls > "$CASE/out"
    assert_no_ssh
    assert_contains "$CASE/out" $'[local]\tlocal session'
    [ ! -e "$HOME/.config/tmuxer/hosts" ]
    run_tr remote register dev outside-config > /dev/null
    clear_logs
    unset TR_HOSTS
    run_tr remote -H all ls > "$CASE/out"
    [ -f "$MOCK_LOG/ssh.dev" ]
    [ -f "$MOCK_LOG/ssh.outside-config" ]
    [ ! -e "$MOCK_LOG/ssh.ignored" ]
    [ ! -e "$MOCK_LOG/ssh.included" ]
    assert_contains "$CASE/out" $'dev\tremote session'
    # The interactive picker uses the same allow list.
    clear_logs
    export MOCK_PICK=$'dev\tremote session\t2\tdetached'
    run_tr remote
    assert_contains "$MOCK_LOG/fzf-input" $'dev\tremote session'
    [ ! -e "$MOCK_LOG/ssh.ignored" ]
    [ ! -e "$MOCK_LOG/ssh.included" ]
    [ ! -e "$CASE/SHOULD_NOT_RUN" ]
    assert_clean
}
test_hosts_filter() {
    printf 'Host ignored\n' > "$HOME/.ssh/config"
    run_tr remote register alpha beta gamma excluded > /dev/null
    export TR_HOSTS=$'alpha beta alpha\ngamma\tunregistered star*'
    run_tr remote -H all ls > "$CASE/out"
    local files=("$MOCK_LOG"/ssh.*)
    [ "${#files[@]}" -eq 3 ]
    local host
    for host in alpha beta gamma; do [ -f "$MOCK_LOG/ssh.$host" ]; done
    [ ! -e "$MOCK_LOG/ssh.excluded" ]
    [ ! -e "$MOCK_LOG/ssh.unregistered" ]
    [ ! -e "$MOCK_LOG/ssh.star*" ]
    clear_logs
    export TR_HOSTS=
    run_tr remote -H all ls > "$CASE/out"
    assert_no_ssh
    # TR_HOSTS only filters discovery; explicit commands may use any registered host.
    run_tr remote -H excluded ls
    [ -f "$MOCK_LOG/ssh.excluded" ]
}
test_unregistered_remote() {
    printf 'Host box\n' > "$HOME/.ssh/config"
    export TR_HOSTS=box
    assert_status 2 run_tr remote -H box ls
    assert_contains "$CASE/err" 'run: tx remote register box'
    assert_status 2 run_tr remote -H box attach
    assert_status 2 run_tr remote -H box
    TR_INTERNAL_PREVIEW=1 assert_status 2 run_tr remote $'box\tsession\t1\tdetached'
    assert_no_ssh
    [ ! -e "$MOCK_LOG/tmux.box" ]
    run_tr remote register box > /dev/null
    run_tr remote -H box ls
    [ -f "$MOCK_LOG/ssh.box" ]
    # Removing the entry revokes access, including previews and picker selections.
    : > "$HOME/.config/tmuxer/hosts"
    clear_logs
    assert_status 2 run_tr remote -H box ls
    TR_INTERNAL_PREVIEW=1 assert_status 2 run_tr remote $'box\tsession\t1\tdetached'
    assert_no_ssh
    assert_status 0 run_tr ls
}
test_all_output() {
    run_tr remote register box dead password > /dev/null
    export TR_HOSTS='box dead password'
    write_row local 'local name:2:0'
    write_row box "  remote's \$;[]  :3:2"
    write_row dead 'invisible:1:0'
    write_row password 'invisible:1:0'
    minimal_path
    run_tr remote -H all ls > "$CASE/out"
    printf "HOST\tSESSION\tWINDOWS\tSTATE\n[local]\tlocal name\t2\tdetached\nbox\t  remote's \$;[]  \t3\tattached\n" > "$CASE/expected"
    /usr/bin/diff -u "$CASE/expected" "$CASE/out"
    assert_contains "$MOCK_LOG/ssh.box" 'BatchMode=yes'
    assert_contains "$MOCK_LOG/ssh.box" 'ConnectTimeout=3'
    assert_contains "$MOCK_LOG/ssh.box" '-T'
    assert_clean
}
test_all_socket() {
    run_tr remote register box > /dev/null
    export TR_HOSTS=box
    run_tr remote -L 'shared socket' -H all ls > "$CASE/out"
    assert_args "$MOCK_LOG/tmux.local" -L 'shared socket' list-sessions -F '#{session_name}:#{session_windows}:#{session_attached}'
    assert_args "$MOCK_LOG/tmux.box" -L 'shared socket' list-sessions -F '#{session_name}:#{session_windows}:#{session_attached}'
}
test_parallel() {
    run_tr remote register barrier-a barrier-b > /dev/null
    export TR_HOSTS='barrier-a barrier-b' MOCK_BARRIER=1
    write_row barrier-a 'first:1:0'
    write_row barrier-b 'second:1:0'
    run_tr remote -H all ls > "$CASE/out"
    assert_contains "$CASE/out" $'barrier-a\tfirst'
    assert_contains "$CASE/out" $'barrier-b\tsecond'
}
selector_fixture() {
    run_tr remote register box > /dev/null
    export TR_HOSTS=box MOCK_EXPECT_CLEAN=1
    SESSION="  odd ' \$;[] name  "
    write_row local "$SESSION:1:0"
    write_row box "$SESSION:2:1"
}
test_select_local() {
    selector_fixture
    export MOCK_PICK=$'[local]\t'"$SESSION"$'\t1\tdetached'
    run_tr remote
    assert_args "$MOCK_LOG/tmux.local" list-sessions -F '#{session_name}:#{session_windows}:#{session_attached}' attach -t "=$SESSION"
    assert_contains "$MOCK_LOG/fzf" '--preview-window'
    assert_clean
}
test_select_nested() {
    selector_fixture
    export TMUX='fake,123,0' MOCK_PICK=$'[local]\t'"$SESSION"$'\t1\tdetached'
    run_tr remote
    assert_args "$MOCK_LOG/tmux.local" list-sessions -F '#{session_name}:#{session_windows}:#{session_attached}' switch-client -t "=$SESSION"
    assert_clean
}
test_select_remote() {
    selector_fixture
    export MOCK_PICK=$'box\t'"$SESSION"$'\t2\tattached'
    run_tr remote
    assert_args "$MOCK_LOG/tmux.box" list-sessions -F '#{session_name}:#{session_windows}:#{session_attached}' attach -t "=$SESSION"
    assert_contains "$MOCK_LOG/ssh.box" '-t'
    assert_clean
}
test_select_revoked() {
    selector_fixture
    export MOCK_REVOKE_REGISTRATION=1 MOCK_PICK=$'box\t'"$SESSION"$'\t2\tattached'
    assert_status 2 run_tr remote
    assert_contains "$CASE/err" 'host is not registered: box'
    assert_args "$MOCK_LOG/tmux.box" list-sessions -F '#{session_name}:#{session_windows}:#{session_attached}'
    assert_clean
}
test_preview_local() {
    selector_fixture
    export MOCK_RUN_PREVIEW=1 MOCK_PICK=$'[local]\t'"$SESSION"$'\t1\tdetached'
    run_tr remote
    assert_args "$MOCK_LOG/tmux.local" list-sessions -F '#{session_name}:#{session_windows}:#{session_attached}' capture-pane -p -t "=$SESSION:" -S -100 attach -t "=$SESSION"
    assert_contains "$MOCK_LOG/preview-output" 'mock pane contents'
    assert_clean
}
test_preview_remote() {
    selector_fixture
    export MOCK_RUN_PREVIEW=1 MOCK_PICK=$'box\t'"$SESSION"$'\t2\tattached'
    run_tr remote
    assert_args "$MOCK_LOG/tmux.box" list-sessions -F '#{session_name}:#{session_windows}:#{session_attached}' capture-pane -p -t "=$SESSION:" -S -100 attach -t "=$SESSION"
    assert_contains "$MOCK_LOG/preview-output" 'mock pane contents'
    assert_clean
}
test_cancel_empty_missing_fzf() {
    export TR_HOSTS=
    assert_status 1 run_tr remote
    assert_contains "$CASE/err" 'no available sessions found'
    [ ! -e "$MOCK_LOG/fzf" ]
    assert_clean
    write_row local 'one:1:0'
    export MOCK_CANCEL=1
    assert_status 130 run_tr remote
    assert_clean
    rm "$CASE/bin/fzf"
    minimal_path
    assert_status 2 run_tr remote
    assert_contains "$CASE/err" 'requires fzf'
    assert_status 0 run_tr ls
    assert_clean
}
test_script_path_spaces() {
    mkdir "$CASE/a directory's"
    cp "$TR" "$CASE/a directory's/tx"
    TR="$CASE/a directory's/tx"
    test_preview_remote
}
test_install() {
    NAME=tm PREFIX="$CASE/prefix space" "$TEST_BASH" "$TEST_ROOT/install.sh" > "$CASE/out"
    [ -x "$CASE/prefix space/bin/tm" ]
    cmp "$TR" "$CASE/prefix space/bin/tm"
    "$CASE/prefix space/bin/tm" --help > "$CASE/out"
    assert_contains "$CASE/out" 'Usage: tm '
    assert_contains "$CASE/out" 'tm remote register host'
    "$CASE/prefix space/bin/tm" remote register custom-host > "$CASE/out"
    "$CASE/prefix space/bin/tm" remote list > "$CASE/out"
    assert_contains "$CASE/out" 'custom-host'
    "$CASE/prefix space/bin/tm" remote -H custom-host ls
    assert_args "$MOCK_LOG/tmux.custom-host" ls
    assert_status 2 "$CASE/prefix space/bin/tm" remote -H unregistered ls
    assert_contains "$CASE/err" 'run: tm remote register unregistered'
    "$TEST_BASH" "$TEST_ROOT/install.sh" > "$CASE/out"
    [ -x "$HOME/.local/bin/tx" ]
    [ ! -e "$HOME/.local/bin/tr" ]
    cmp "$TR" "$HOME/.local/bin/tx"
    PATH="$HOME/.local/bin:$CASE/bin:/usr/bin:/bin"
    export PATH
    tx --help > "$CASE/out"
    assert_contains "$CASE/out" 'Usage: tx '
    assert_contains "$CASE/out" 'tx remote register host'
    tx remote register registered > "$CASE/out"
    tx remote list > "$CASE/out"
    assert_contains "$CASE/out" 'registered'
    tx remote -H registered ls
    assert_args "$MOCK_LOG/tmux.registered" ls
    assert_status 2 tx remote -H unregistered ls
    assert_contains "$CASE/err" 'run: tx remote register unregistered'
    assert_status 2 tx remote -H
    assert_contains "$CASE/err" 'tx: -H requires a host argument'
    tx ls
    assert_args "$MOCK_LOG/tmux.local" ls
    # NVM uses this conversion during shell startup. It must reach system tr.
    [ "$(printf t | command tr t '\t')" = $'\t' ]
    assert_status 2 env NAME='../bad' PREFIX="$CASE/prefix" "$TEST_BASH" "$TEST_ROOT/install.sh"
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
    run_tr remote -H all ls > "$CASE/out"
    assert_contains "$CASE/out" $'[local]\t'"$session"$'\t1\tdetached'
    TR_INTERNAL_PREVIEW=1 run_tr remote $'[local]\t'"$session"$'\t1\tdetached' > "$CASE/preview"
    assert_contains "$CASE/preview" 'TR_REAL_OK'
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
    unset XDG_CONFIG_HOME TMUX TMUX_TMPDIR TR_HOSTS TR_INTERNAL_PREVIEW MOCK_HOST MOCK_TMUX_STATUS MOCK_CANCEL MOCK_PICK MOCK_RUN_PREVIEW MOCK_BARRIER MOCK_EXPECT_CLEAN MOCK_REVOKE_REGISTRATION
    cd "$CASE"
    "test_$2"
    exit 0
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/tr-tests.XXXXXXXX")
trap 'rm -rf "$WORK"' EXIT
export WORK TEST_BASH ORIGINAL_PATH REAL_TMUX
tests='local_forward local_default local_namespace remote_quotes exit_status global_options non_tty tty_attach tty_other errors_help remote_list register register_concurrent register_invalid register_config_path register_io_errors allowlist_discovery hosts_filter unregistered_remote all_output all_socket parallel select_local select_nested select_remote select_revoked preview_local preview_remote cancel_empty_missing_fzf script_path_spaces install real_tmux'
passed=0
failed=0
for test in $tests; do
    if "$TEST_BASH" "$0" --case "$test" > "$WORK/output" 2>&1; then
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
