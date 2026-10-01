# tr

Manage local and remote tmux sessions through the system ssh command. A single Bash script compatible with macOS's built-in Bash 3.2 and common Linux distributions. No server agent is needed.

Local commands require tmux. Remote commands require local ssh and tmux on the server. Interactive selection also requires local fzf. Scanning uses awk and the standard mktemp and rm utilities; column, Python, Node, and SSH libraries are not required.

## Installation

```bash
git clone https://github.com/ryqdev/tmuxer.git
cd tmuxer
./install.sh                     # ~/.local/bin/tr
NAME=tx ./install.sh             # ~/.local/bin/tx (recommended)
PREFIX=/usr/local NAME=rt ./install.sh  # /usr/local/bin/rt; requires write permission
export PATH="$HOME/.local/bin:$PATH"
```

You can also run `./tr` directly. The examples below use the default name; substitute tx or rt if you install under another name.

## Name collision warning

**`tr` shares its name with the system character translation command.** If the installation directory comes before `/usr/bin` in PATH, it will shadow the system command and may affect other scripts. Install with `NAME=tx ./install.sh` or `NAME=rt ./install.sh` to avoid this. Use `/usr/bin/tr` when you need the system command. This tool never calls the system tr internally.

## Usage

| tmux command | Local tr command | Remote tr command |
| --- | --- | --- |
| `tmux ls` | `tr ls` | `tr -H dev ls` |
| `tmux new-session -s work` | `tr new-session -s work` | `tr -H dev new-session -s work` |
| `tmux attach -t '=work'` | `tr attach -t '=work'` | `tr -H dev attach -t '=work'` |
| `tmux send-keys -t '=work:' 'echo hello' Enter` | `tr send-keys -t '=work:' 'echo hello' Enter` | `tr -H dev send-keys -t '=work:' 'echo hello' Enter` |
| `tmux capture-pane -p -t '=work:'` | `tr capture-pane -p -t '=work:'` | `tr -H dev capture-pane -p -t '=work:'` |
| `tmux kill-session -t '=work'` | `tr kill-session -t '=work'` | `tr -H dev kill-session -t '=work'` |
| `tmux -L project ls` | `tr -L project ls` | `tr -H dev -L project ls` |

Place `-H` before the tmux subcommand; it may appear between tmux global options. All other arguments are preserved, including empty arguments, spaces, and quotes. Each remote argument is escaped with POSIX shell single quotes. Run `tr --help` for help.

There are two behavioral differences from tmux:

1. **`tr` with no arguments** scans local and SSH hosts in parallel, then opens fzf with the active pane's latest 100 lines in a preview on the right. Selecting a local session uses `switch-client` when already inside tmux, otherwise `attach`. Remote selection uses `ssh -t` and `attach -t '=session-name'` for an exact match. Canceling exits; no available sessions returns status 1.
2. **`tr -H all ls`** lists sessions on this machine and all hosts. Output is tab-separated with `HOST / SESSION / WINDOWS / STATE` columns. The local host is labeled `[local]`; state is attached or detached. `-H all` only supports `ls`, with optional tmux global options before the subcommand, such as `tr -H all -L project ls`.

Other commands execute local tmux or system ssh directly. Remote commands use `ssh -t` only when stdin is a terminal and the subcommand is `attach`, `attach-session`, `a`, `at`, `new`, `new-session`, or absent. Other calls use `ssh -T`, so output can be piped or redirected:

```bash
tr -H dev capture-pane -p -t '=work:' > pane.txt
tr -H dev send-keys -t '=work:' "python x.py --a 'b c'" Enter
```

## Host discovery and SSH configuration

By default, aliases are collected from Host entries in `~/.ssh/config`. Multiple aliases per line, comments, deduplication, and Include directives with glob patterns, nested files, and paths containing spaces are supported. Relative Include paths are resolved under `~/.ssh`; cyclic includes are bounded. Wildcard and negated Host patterns are not enumerated. Parsing only collects aliases and never executes Match exec; system ssh handles the actual connection configuration.

```bash
TR_HOSTS="dev staging prod" tr    # Override host discovery; duplicates are removed
TR_HOSTS="" tr                   # Scan only this machine
tr -H 192.0.2.10 ls              # Explicit hosts need not appear in the discovered list
```

Enable connection reuse by placing these general settings after your specific Host entries:

```sshconfig
Host dev
    HostName dev.example.com
    User alice
    IdentityFile ~/.ssh/id_ed25519
    # ProxyJump bastion

Host *
    ControlMaster auto
    ControlPath ~/.ssh/cm-%C
    ControlPersist 10m
```

SSH aliases, ProxyJump, ControlMaster, and ssh-agent work through system ssh. Scans and remote previews set `BatchMode=yes`, `ConnectTimeout=3`, and `ConnectionAttempts=1`. Hosts that cannot connect, require a password, lack tmux, or have no sessions are skipped. Authentication for direct `tr -H dev ...` commands is still handled by ssh.

## Troubleshooting

- **A host is missing from the list:** The list shows sessions, so hosts with no sessions do not appear. Check that the alias is a literal Host entry and TR_HOSTS has not overridden it. Run `ssh dev` manually to accept its host key and configure keys or ssh-agent, then check `tr -H dev ls`. Password prompts, timeouts, tmux missing from the remote PATH, or no sessions cause scans to skip the host. Include discovery collects declared aliases; their usability still depends on ssh's conditional configuration.
- **Nested tmux prefix conflicts:** Attaching to remote tmux from local tmux creates nesting. With the default prefix, press `Ctrl-b Ctrl-b` to send a prefix to the inner session, then press the desired key. You can also configure different prefixes for the inner and outer servers.
- **Custom sockets:** Use `tr -L project ls` or `tr -S /path/to/socket ls`; remotely, use `tr -H dev -L project ls`. The `-S` path is interpreted on the target host. Aggregate listing supports `tr -H all -L project ls`. The no-argument selector uses each host's default socket, honoring the local TMUX/TMUX_TMPDIR environment. To enter a session on another socket, specify its socket option and attach explicitly.
- **Missing fzf or column:** Only the no-argument selector needs fzf. Explicit commands and aggregate listing do not. Output uses tabs and never calls column.

## Tests

```bash
bash -n tr install.sh tests/run.sh tests/mocks/*
bash tests/run.sh
# Explicitly test the built-in Bash on macOS:
TEST_BASH=/bin/bash /bin/bash tests/run.sh
# If shellcheck is installed:
shellcheck --severity=error tr install.sh tests/run.sh tests/mocks/*
```

Tests require local tmux and use the system script(1) utility for terminal tests; bats is not needed. Real tmux runs with a temporary TMUX_TMPDIR under `/tmp` and isolated `-L` / `-S` sockets to avoid UNIX socket path length limits and leave existing servers untouched.

Mock ssh and fzf cover quoting, empty arguments and newlines, TTY and non-TTY behavior, global options, invalid input, Include and TR_HOSTS discovery, parallel scans, aggregate output, selection, previews, and temporary directory cleanup. Real local tmux tests cover creation, listing, send-keys, capture-pane, kill-session, and both socket options. Mocks do not validate real SSH networking, authentication, ProxyJump, ControlMaster, or the actual fzf interface.

## License

[MIT License](LICENSE). Copyright (c) 2026 ryqdev.
