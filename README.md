# tx

Use `tx` for local tmux and `tx remote` for tmux on a registered SSH server. A leading `@host` is a server reference: `tx remote @dev ls` runs `tmux ls` on `dev`. Omit the reference to choose a server with fzf, then run the same tmux command.

| Command | Usage |
| --- | --- |
| `tx` | Select a local session with a pane preview (requires fzf) |
| `tx [tmux arguments...]` | Run a tmux command locally |
| `tx remote @host [tmux arguments...]` | Run tmux on the referenced registered server |
| `tx remote [tmux arguments...]` | Select a registered server, then run tmux (requires fzf and an interactive terminal) |
| `tx hosts list` | List registered servers without connecting |
| `tx hosts candidates` | List SSH aliases available for registration |
| `tx hosts register <host> [host ...]` | Add configured SSH aliases to the persistent allow list |
| `tx hosts delete <host> [host ...]` | Remove registered servers from the allow list |
| `tx hosts help` | Show host management help |
| `tx help` | Show help |

Only the first argument immediately after `remote` can be a server reference. Remove its leading `@` to get the exact registered destination; everything else is passed unchanged to tmux. This keeps server names distinct from tmux commands, including when a server is named `ls`:

```bash
tx remote @ls ls   # Run tmux ls on the server named ls
tx remote ls       # Choose a server, then run tmux ls
```

Bare server names are tmux arguments, so use `@dev`, rather than `dev`, to reference a server. References in later arguments, such as a tmux target or an argument to `send-keys`, remain untouched. Legacy destinations containing `@` also work: `@user@dev` references the registered destination `user@dev`, and `@@dev` references `@dev`.

With no tmux arguments, `tx remote @dev` runs the remote tmux default command. Bare `tx remote` chooses a server first, then runs that same default command. Neither form scans remote sessions or automatically selects an existing session. Use `tx remote @dev attach -t work` to attach to a known session.

Bare `tx` still selects an existing local session. Except for `help`, `hosts`, and `remote`, arguments are passed unchanged to local tmux. Local commands and selection do not read the remote allow list or require SSH. Explicit local tmux commands and remote commands with `@host` do not require fzf.

## Installation

Requires Bash 3.2+ and tmux. Remote execution also requires SSH and tmux on the remote host. Install fzf for local session selection and remote server selection. Host registration, deletion, and listing do not require tmux, SSH, or fzf. Registration and listing SSH candidates additionally use awk.

```bash
git clone https://github.com/ryqdev/tmuxer.git
cd tmuxer
./install.sh
export PATH="$HOME/.local/bin:$PATH"
tx help
```

The installer copies `tx` to `~/.local/bin/tx`. Add the `export PATH` line to your shell configuration (such as `~/.zshrc` or `~/.bashrc`) to make it permanent.

Set `PREFIX` to change the installation directory; the command is installed in `$PREFIX/bin`. Set `NAME` to change the command name:

```bash
NAME=tm ./install.sh
```

Use your chosen name in place of `tx` in the examples below. Avoid `NAME=tr`: it shadows the system text-processing command used by shell scripts, including NVM.

### Zsh completion

The installer also copies the Zsh completion script to `$PREFIX/share/tmuxer/tx.zsh`. Load it in `~/.zshrc` after your shell framework initializes completion (or after `autoload -Uz compinit; compinit`):

```zsh
source "$HOME/.local/share/tmuxer/tx.zsh" tx
```

Run the same `source` command in your current shell to enable it immediately. For a custom `PREFIX` or `NAME`, use the exact command printed by the installer.

Tab completes `tx remote @de` to `tx remote @dev`, SSH aliases after `hosts register`, registered hosts after `hosts delete`, and host management subcommands. Server reference completion reads the local allow list without connecting over SSH and is independent of `TR_HOSTS`. Local and remote tmux commands reuse Zsh's tmux command and option completion, including after `@host`. Dynamic session and target suggestions come from the local tmux completer, not from the remote server.

### Upgrading from tr

Older versions installed the wrapper as `tr`, which can cause `unknown command: t` during shell startup. If `~/.local/bin/tr` is the old tmuxer wrapper, move it aside before installing `tx`:

```bash
mv "$HOME/.local/bin/tr" "$HOME/.local/bin/tr-tmux-backup"
./install.sh
hash -r
```

For a custom `PREFIX`, move the old wrapper from `$PREFIX/bin/tr` instead. Update any tmuxer aliases or scripts to call `tx`. The `TR_HOSTS` environment variable is still supported.

### Upgrading remote commands

Existing allow-list files continue to work. Host management now lives under `hosts`; remote execution uses server references:

| Previous command | New command |
| --- | --- |
| `tx remote exec dev ls` | `tx remote @dev ls` |
| `tx remote exec dev` | `tx remote @dev` |
| `tx remote register dev` | `tx hosts register dev` |
| `tx remote delete dev` | `tx hosts delete dev` |
| `tx remote list` | `tx hosts list` |
| `tx remote candidates` | `tx hosts candidates` |
| `tx remote help` | `tx help` |
| `tx remote` / `tx remote select` (session picker) | `tx remote` now selects a server and runs its tmux default command |
| `tx remote sessions` (cross-server summary) | `tx remote ls` selects one server; use `tx remote @dev ls` to query a specific server |
| `tx -H dev ls` / `tx remote -H dev ls` | `tx remote @dev ls` |
| `tx register dev` | `tx hosts register dev` |
| `tx --help` / `tx remote --help` | `tx help` |

The remote `exec`, `sessions`, and `select` wrapper subcommands have been removed. `remote` now passes all arguments after the optional leading reference to tmux, including former wrapper subcommands. Update scripts to use the new forms. Cross-server session discovery and summaries have been removed; `tx remote ls` executes on exactly one chosen server. Local `tx` session selection is unchanged.

## Examples

```bash
# Local sessions
tx
tx ls
tx new-session -s work
tx attach -t '=work'

# Register servers from your SSH config
tx hosts candidates
tx hosts register dev staging
tx hosts list

# Run tmux on a specific server
tx remote @dev ls
tx remote @dev new-session -s work
tx remote @dev attach -t '=work'
tx remote @dev kill-session -t '=work'

# Omit the reference to choose a server first
tx remote
tx remote ls
tx remote new-session -s work

# Send input and capture pane output
tx remote @dev send-keys -t '=work:' 'echo hello' Enter
tx remote @dev capture-pane -p -t '=work:' > pane.txt
printf '%s\n' 'buffer contents' | tx remote @dev load-buffer -

# Put tmux global options before the tmux subcommand
tx -L project ls
tx remote @dev -S /path/to/socket ls
tx remote -L project ls
```

The remote server picker uses the local registration list and does not connect to servers before selection. Servers without sessions, offline servers, and servers requiring a password are still offered. Only the selected server receives the tmux command; SSH uses your normal configuration and authentication.

The picker shows the command to run and requires fzf and an interactive terminal. It preserves stdin for tmux and keeps the command's stdout available for piping or redirection. Cancelling exits without connecting (Escape/Ctrl-C returns status 130). An absent or empty registration list, or an empty `TR_HOSTS` filter, reports no available registered hosts and exits with status 1. Without an interactive terminal, specify `@host`; the command reports this requirement and exits with status 2. Invalid or unregistered references also fail before connecting.

## Hosts

Find server aliases in your SSH configuration before registering them:

```bash
tx hosts candidates
# dev
# staging
tx hosts register dev staging
```

`tx hosts candidates` reads concrete `Host` aliases from `~/.ssh/config`, including nested `Include` files. It prints each alias once, in configuration order, with one alias per line. Wildcard and negated patterns, the reserved name `all`, and names rejected by `hosts register` are skipped. It lists aliases whether or not they are already registered, independently of `TR_HOSTS` and the allow-list file. A missing or empty SSH config produces no output.

Include paths support absolute paths, paths relative to `~/.ssh`, `~/` paths, double quotes, and globs in lexical order. Repeated files and include cycles are skipped. Dynamic paths using SSH tokens, environment variables, or other users' `~user` paths are not expanded. This is a list of configured candidates: it does not evaluate `Host`/`Match` conditions, execute `Match exec` commands, connect to servers, or change the allow list.

`tx hosts register` saves aliases in `${XDG_CONFIG_HOME:-$HOME/.config}/tmuxer/hosts` (normally `~/.config/tmuxer/hosts`). Pass raw SSH aliases here, without adding the reference prefix: `tx hosts register dev`, then `tx remote @dev ls`. Every input must exactly match an alias listed by `tx hosts candidates`. If any input is invalid, the entire registration fails without changing the allow list. Missing, empty, or malformed SSH configuration cannot authorize registration.

For a destination such as `user@192.0.2.10`, first define an alias in `~/.ssh/config`, then register that alias:

```sshconfig
Host prod
    HostName 192.0.2.10
    User user
```

```bash
tx hosts register prod
tx remote @prod ls
```

Registration checks local configuration without connecting to the server; it does not verify reachability. Repeated registration does not add duplicates. Wildcards, whitespace, and the reserved name `all` are rejected. Existing allow-list entries remain available to `hosts list`, server selection, and explicit references even if they are absent from the current SSH candidates; registering them again requires a matching candidate. References must match the exact registered destination: `dev` and `user@dev` are separate entries.

`tx hosts list` prints every registered destination once, in registration order, with one destination per line. It does not connect to servers and is not filtered by `TR_HOSTS`. An absent or empty allow list produces no output. SSH config entries are not automatically registered.

Use `TR_HOSTS` to filter the server picker. Unregistered names are ignored; duplicates are removed:

```bash
TR_HOSTS="dev staging" tx remote ls
TR_HOSTS="" tx remote ls            # No available hosts
TR_HOSTS="dev" tx remote @prod ls   # Explicit references bypass the picker filter
```

The picker rechecks registration after selection, before connecting. Removing a host while the picker is open revokes access.

Remove one or more registered servers with:

```bash
tx hosts delete dev staging
tx hosts list
```

`tx hosts delete` removes every occurrence of the exact destinations from the allow list, including legacy entries absent from SSH configuration. All names must be registered and syntactically valid; if any name is invalid or unknown, the entire deletion fails without changing the file. Deletion reads only the allow list and is independent of `TR_HOSTS`. Comments, blank lines, and the order of retained entries are preserved. The file is replaced atomically, with register/delete operations serialized to preserve concurrent changes.

You can also edit the allow-list file directly. It contains one destination per line; blank lines and lines starting with `#` are ignored. The `@` reference prefix belongs to the command line, not to the stored alias.

Local selection with bare `tx` shows session names, window counts, attached/detached state, and a pane preview. Selecting a session switches clients if already inside tmux, or attaches otherwise. If there are no local sessions, it exits with status 1.
