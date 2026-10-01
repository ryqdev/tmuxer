#!/usr/bin/env bash
# No bats dependency. script(1) supplies a PTY; real tmux uses isolated sockets.
set -eu

TEST_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TR=$TEST_ROOT/tr
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
    for tool in bash awk sed mktemp rm; do ln -s "$(command -v "$tool")" "$CASE/bin/$tool"; done
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
test_remote_quotes() {
    run_tr -H box send-keys 'python x.py --a '\''b c'\''' '' "''''" 'a"b' '$HOME; $(touch nope)' $'two\nlines' '\path' </dev/null
    assert_args "$MOCK_LOG/tmux.box" send-keys 'python x.py --a '\''b c'\''' '' "''''" 'a"b' '$HOME; $(touch nope)' $'two\nlines' '\path'
    assert_contains "$MOCK_LOG/ssh.box" '-T'
    [ ! -e "$CASE/nope" ]
}
test_exit_status() {
    export MOCK_TMUX_STATUS=37
    assert_status 37 run_tr ls
    assert_status 37 run_tr -H box ls
}
test_global_options() {
    run_tr -L 'local socket' ls
    assert_args "$MOCK_LOG/tmux.local" -L 'local socket' ls
    run_tr -S '/tmp/a b' -H box -f 'my config' -T 'flags' -c 'shell command' -v capture-pane -p
    assert_args "$MOCK_LOG/tmux.box" -S '/tmp/a b' -f 'my config' -T flags -c 'shell command' -v capture-pane -p
    clear_logs
    run_tr -H box -L -H ls
    assert_args "$MOCK_LOG/tmux.box" -L -H ls
    clear_logs
    run_tr -H box -- send-keys -H
    assert_args "$MOCK_LOG/tmux.box" -- send-keys -H
}
test_non_tty() {
    local command
    for command in attach attach-session a at new new-session ls capture-pane send-keys ''; do
        clear_logs
        if [ -n "$command" ]; then run_tr -H box "$command" </dev/null; else run_tr -H box </dev/null; fi
        assert_contains "$MOCK_LOG/ssh.box" '-T'
    done
    run_tr -H box capture-pane -p | awk '{print}' > "$CASE/piped"
    assert_contains "$CASE/piped" 'mock pane contents'
}
test_tty_attach() {
    local command
    for command in attach attach-session a at new new-session ''; do
        clear_logs
        if [ -n "$command" ]; then run_tty -H box -L 'socket space' "$command";
        else run_tty -H box -S '/tmp/my socket'; fi
        assert_contains "$MOCK_LOG/ssh.box" '-t'
    done
    clear_logs
    run_tty -H box -vLsocket -S '/tmp/my socket' -f attach -T new -c a at
    assert_contains "$MOCK_LOG/ssh.box" '-t'
}
test_tty_other() {
    local command
    for command in ls capture-pane send-keys; do
        clear_logs
        run_tty -H box -L attach -S new "$command"
        assert_contains "$MOCK_LOG/ssh.box" '-T'
    done
}
test_errors_help() {
    assert_status 2 run_tr -H
    assert_contains "$CASE/err" '-H requires a host argument'
    assert_status 2 run_tr -H ''
    assert_status 2 run_tr -H --help
    assert_status 2 run_tr -H all
    assert_status 2 run_tr -H all new
    assert_status 2 run_tr -H all list-sessions
    assert_status 2 run_tr -H all ls extra
    assert_status 0 run_tr --help
    assert_contains "$CASE/out" 'TR_HOSTS'
    [ ! -e "$MOCK_LOG/tmux.local" ]
    [ ! -e "$MOCK_LOG/ssh.all" ]
}
test_config_hosts() {
    mkdir -p "$HOME/.ssh/config.d" "$HOME/.ssh/more" "$HOME/absolute"
    cat > "$HOME/.ssh/config" <<'CONFIG'
Host root alias root * wild? !negative [pattern] # comment
HOST=equal
host = equal-spaced
Host ="equal-quoted"
Include "config.d/*.conf" "extra config" ~/absolute/hosts
Match exec "touch SHOULD_NOT_RUN"
Host after
CONFIG
    cat > "$HOME/.ssh/config.d/one.conf" <<'CONFIG'
Host child alias
Include more/nested.conf
Include config
CONFIG
    printf 'Host nested\nInclude ../.ssh/config\n' > "$HOME/.ssh/more/nested.conf"
    printf 'Host space-file\n' > "$HOME/.ssh/extra config"
    printf 'Host absolute\n' > "$HOME/absolute/hosts"
    run_tr -H all ls > "$CASE/out"
    local host count=0
    for host in root alias equal equal-spaced equal-quoted child nested space-file absolute after; do
        [ -f "$MOCK_LOG/ssh.$host" ] || fail "host not parsed: $host"
        count=$((count + 1))
    done
    local files=("$MOCK_LOG"/ssh.*)
    [ "${#files[@]}" -eq "$count" ] || fail 'unexpected / duplicate hosts'
    [ ! -e "$CASE/SHOULD_NOT_RUN" ]
    assert_clean
}
test_hosts_override() {
    printf 'Host ignored\n' > "$HOME/.ssh/config"
    export TR_HOSTS=$'alpha beta alpha\ngamma\tstar*'
    run_tr -H all ls > "$CASE/out"
    local files=("$MOCK_LOG"/ssh.*)
    [ "${#files[@]}" -eq 4 ]
    local host
    for host in alpha beta gamma 'star*'; do [ -f "$MOCK_LOG/ssh.$host" ]; done
    clear_logs
    export TR_HOSTS=
    run_tr -H all ls > "$CASE/out"
    for host in "$MOCK_LOG"/ssh.*; do [ ! -f "$host" ]; done
}
test_all_output() {
    export TR_HOSTS='box dead password'
    write_row local 'local name:2:0'
    write_row box "  remote's \$;[]  :3:2"
    write_row dead 'invisible:1:0'
    write_row password 'invisible:1:0'
    minimal_path
    run_tr -H all ls > "$CASE/out"
    printf "HOST\tSESSION\tWINDOWS\tSTATE\n[local]\tlocal name\t2\tdetached\nbox\t  remote's \$;[]  \t3\tattached\n" > "$CASE/expected"
    /usr/bin/diff -u "$CASE/expected" "$CASE/out"
    assert_contains "$MOCK_LOG/ssh.box" 'BatchMode=yes'
    assert_contains "$MOCK_LOG/ssh.box" 'ConnectTimeout=3'
    assert_contains "$MOCK_LOG/ssh.box" '-T'
    assert_clean
}
test_all_socket() {
    export TR_HOSTS=box
    run_tr -L 'shared socket' -H all ls > "$CASE/out"
    assert_args "$MOCK_LOG/tmux.local" -L 'shared socket' list-sessions -F '#{session_name}:#{session_windows}:#{session_attached}'
    assert_args "$MOCK_LOG/tmux.box" -L 'shared socket' list-sessions -F '#{session_name}:#{session_windows}:#{session_attached}'
}
test_parallel() {
    export TR_HOSTS='barrier-a barrier-b' MOCK_BARRIER=1
    write_row barrier-a 'first:1:0'
    write_row barrier-b 'second:1:0'
    run_tr -H all ls > "$CASE/out"
    assert_contains "$CASE/out" $'barrier-a\tfirst'
    assert_contains "$CASE/out" $'barrier-b\tsecond'
}
selector_fixture() {
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
    assert_clean
}
test_select_nested() {
    selector_fixture
    export TMUX='fake,123,0' MOCK_PICK=$'[local]\t'"$SESSION"$'\t1\tdetached'
    run_tr
    assert_args "$MOCK_LOG/tmux.local" list-sessions -F '#{session_name}:#{session_windows}:#{session_attached}' switch-client -t "=$SESSION"
    assert_clean
}
test_select_remote() {
    selector_fixture
    export MOCK_PICK=$'box\t'"$SESSION"$'\t2\tattached'
    run_tr
    assert_args "$MOCK_LOG/tmux.box" list-sessions -F '#{session_name}:#{session_windows}:#{session_attached}' attach -t "=$SESSION"
    assert_contains "$MOCK_LOG/ssh.box" '-t'
    assert_clean
}
test_preview_local() {
    selector_fixture
    export MOCK_RUN_PREVIEW=1 MOCK_PICK=$'[local]\t'"$SESSION"$'\t1\tdetached'
    run_tr
    assert_args "$MOCK_LOG/tmux.local" list-sessions -F '#{session_name}:#{session_windows}:#{session_attached}' capture-pane -p -t "=$SESSION:" -S -100 attach -t "=$SESSION"
    assert_contains "$MOCK_LOG/preview-output" 'mock pane contents'
    assert_clean
}
test_preview_remote() {
    selector_fixture
    export MOCK_RUN_PREVIEW=1 MOCK_PICK=$'box\t'"$SESSION"$'\t2\tattached'
    run_tr
    assert_args "$MOCK_LOG/tmux.box" list-sessions -F '#{session_name}:#{session_windows}:#{session_attached}' capture-pane -p -t "=$SESSION:" -S -100 attach -t "=$SESSION"
    assert_contains "$MOCK_LOG/preview-output" 'mock pane contents'
    assert_clean
}
test_cancel_empty_missing_fzf() {
    export TR_HOSTS=
    assert_status 1 run_tr
    assert_contains "$CASE/err" 'no available sessions found'
    [ ! -e "$MOCK_LOG/fzf" ]
    assert_clean
    write_row local 'one:1:0'
    export MOCK_CANCEL=1
    assert_status 130 run_tr
    assert_clean
    rm "$CASE/bin/fzf"
    minimal_path
    assert_status 2 run_tr
    assert_contains "$CASE/err" 'requires fzf'
    assert_status 0 run_tr ls
    assert_clean
}
test_script_path_spaces() {
    mkdir "$CASE/a directory's"
    cp "$TR" "$CASE/a directory's/tr"
    TR="$CASE/a directory's/tr"
    test_preview_remote
}
test_install() {
    NAME=tx PREFIX="$CASE/prefix space" "$TEST_BASH" "$TEST_ROOT/install.sh" > "$CASE/out"
    [ -x "$CASE/prefix space/bin/tx" ]
    cmp "$TR" "$CASE/prefix space/bin/tx"
    "$TEST_BASH" "$TEST_ROOT/install.sh" > "$CASE/out"
    [ -x "$HOME/.local/bin/tr" ]
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
    run_tr -H all ls > "$CASE/out"
    assert_contains "$CASE/out" $'[local]\t'"$session"$'\t1\tdetached'
    TR_INTERNAL_PREVIEW=1 run_tr $'[local]\t'"$session"$'\t1\tdetached' > "$CASE/preview"
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
    unset TMUX TMUX_TMPDIR TR_HOSTS TR_INTERNAL_PREVIEW MOCK_HOST MOCK_TMUX_STATUS MOCK_CANCEL MOCK_PICK MOCK_RUN_PREVIEW MOCK_BARRIER MOCK_EXPECT_CLEAN
    cd "$CASE"
    "test_$2"
    exit 0
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/tr-tests.XXXXXXXX")
trap 'rm -rf "$WORK"' EXIT
export WORK TEST_BASH ORIGINAL_PATH REAL_TMUX
tests='local_forward remote_quotes exit_status global_options non_tty tty_attach tty_other errors_help config_hosts hosts_override all_output all_socket parallel select_local select_nested select_remote preview_local preview_remote cancel_empty_missing_fzf script_path_spaces install real_tmux'
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
