# tx

Use `tx` to select a local tmux session with fzf, and `tx remote` to select a session across registered SSH servers. `tx remote @dev` opens the same session picker for `dev` alone. With tmux arguments, `tx ls` runs local `tmux ls` and `tx remote @dev ls` runs `tmux ls` on `dev`.

| Command | Usage |
| --- | --- |
| `tx` | Select a local session with a pane preview (requires fzf) |
| `tx [tmux arguments...]` | Run a tmux command locally |
| `tx remote` | Select a session across registered servers with a pane preview |
| `tx remote @host` | Select a session on one registered server with a pane preview |
| `tx remote @host <tmux arguments...>` | Run tmux on the referenced registered server |
| `tx hosts list` | List registered servers without connecting |
| `tx hosts candidates` | List SSH aliases available for registration |
| `tx hosts register <host> [host ...]` | Add configured SSH aliases to the persistent allow list |
| `tx hosts remove <host> [host ...]` | Remove registered servers from the allow list |
| `tx hosts help` | Show host management help |
| `tx help` | Show help |

Every remote tmux command requires a server reference immediately after `remote`. Remove its leading `@` to get the exact registered destination; everything after the reference is passed unchanged to tmux. This keeps server names distinct from tmux commands, including when a server is named `ls`:

```bash
tx remote @ls ls   # Run tmux ls on the server named ls
tx remote ls       # Error: a command requires @host
```

Use `@dev` to reference a server; `tx remote dev` is an error. References in later arguments, such as a tmux target or an argument to `send-keys`, remain untouched. Legacy destinations containing `@` also work: `@user@dev` references the registered destination `user@dev`, and `@@dev` references `@dev`.

With no tmux arguments, `tx remote @dev` lists existing sessions on `dev` in fzf and attaches to the selected session. Bare `tx remote` lists sessions across registered servers in one picker, with the server name on each row. Both require local fzf and an interactive terminal. Use `tx remote @dev attach -t work` to attach directly to a known session, or `tx remote @dev new-session -s work` to create one.

Bare `tx` still selects an existing local session. Except for `help`, `hosts`, and `remote`, arguments are passed unchanged to local tmux. Local commands and selection do not read the remote allow list or require SSH. Explicit local tmux commands and `tx remote @host` with tmux arguments do not require fzf.

## Installation

Requires Bash 3.2+ and tmux. Remote execution also requires SSH and tmux on the remote host. Install fzf locally for session selection; remote servers do not need fzf or this wrapper. Host registration, removal, and listing do not require tmux, SSH, or fzf. Registration and listing SSH candidates additionally use awk.

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

Tab completes `tx remote @de` to `tx remote @dev`, SSH aliases after `hosts register`, registered hosts after `hosts remove`, and host management subcommands. Server reference completion reads the local allow list without connecting over SSH and is independent of `TR_HOSTS`. Local commands and remote commands after `@host` reuse Zsh's tmux command and option completion. Commands without a remote reference are not suggested. Dynamic session and target suggestions come from the local tmux completer, not from the remote server.

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
| `tx remote exec dev` (tmux default command) | `tx remote @dev new-session` |
| `tx remote register dev` | `tx hosts register dev` |
| `tx remote delete dev` | `tx hosts remove dev` |
| `tx hosts delete dev` | `tx hosts remove dev` |
| `tx remote list` | `tx hosts list` |
| `tx remote candidates` | `tx hosts candidates` |
| `tx remote help` | `tx help` |
| `tx remote select` | `tx remote` selects a session across registered servers |
| `tx remote sessions` (cross-server summary) | `tx remote` for interactive selection; `tx remote @dev ls` to list one server |
| `tx remote ls` / `tx remote new-session ...` (server picker) | Add a reference: `tx remote @dev ls` / `tx remote @dev new-session ...` |
| `tx remote @dev` (tmux default command) | Now selects an existing session; use `tx remote @dev new-session` to create one |
| `tx -H dev ls` / `tx remote -H dev ls` | `tx remote @dev ls` |
| `tx register dev` | `tx hosts register dev` |
| `tx --help` / `tx remote --help` | `tx help` |

The remote `exec`, `sessions`, and `select` wrapper subcommands remain removed. Only bare `tx remote` can omit a server reference. After `@host`, every argument goes to tmux, including former wrapper subcommands. Local session selection and command forwarding are unchanged.

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

# Select an existing remote session
tx remote
tx remote @dev

# Run tmux on a specific server
tx remote @dev ls
tx remote @dev new-session -s work
tx remote @dev attach -t '=work'
tx remote @dev kill-session -t '=work'

# Send input and capture pane output
tx remote @dev send-keys -t '=work:' 'echo hello' Enter
tx remote @dev capture-pane -p -t '=work:' > pane.txt
printf '%s\n' 'buffer contents' | tx remote @dev load-buffer -

# Put tmux global options before the tmux subcommand
tx -L project ls
tx remote @dev -S /path/to/socket ls
tx remote @dev -L project ls
```

All session pickers show the host, session name, window count, attached/detached state, and the last 100 lines of a pane preview. Local selection switches clients when already inside tmux and attaches otherwise. Remote selection always connects over SSH and attaches to the chosen server's session.

`tx remote` queries registered servers concurrently, without querying local sessions. Discovery uses noninteractive SSH authentication with a three-second connection timeout and one connection attempt. Unreachable servers, servers requiring interactive authentication, and servers with no sessions contribute no rows. `tx remote @dev` queries only `dev`, allows normal SSH authentication, and reports SSH/tmux errors with their exit status. Remote previews use noninteractive SSH authentication; interactive authentication alone does not support previews. Explicit tmux commands use your normal SSH configuration and authentication, preserve stdin, and keep stdout available for piping or redirection.

Cancelling a picker exits without attaching (Escape/Ctrl-C returns status 130), although remote discovery and previews may already have connected. An absent or empty registration list, or an empty `TR_HOSTS` filter, reports no available registered hosts and exits with status 1. A picker with no available sessions also exits with status 1. Missing fzf, a noninteractive remote picker, commands without `@host`, and invalid or unregistered references exit with status 2. Explicit tmux commands such as `tx remote @dev ls` work without fzf or an interactive terminal.

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

Registration checks local configuration without connecting to the server; it does not verify reachability. Repeated registration does not add duplicates. Wildcards, whitespace, and the reserved name `all` are rejected. Existing allow-list entries remain available to `hosts list`, remote session discovery, and explicit references even if they are absent from the current SSH candidates; registering them again requires a matching candidate. References must match the exact registered destination: `dev` and `user@dev` are separate entries.

`tx hosts list` prints every registered destination once, in registration order, with one destination per line. It does not connect to servers and is not filtered by `TR_HOSTS`. An absent or empty allow list produces no output. SSH config entries are not automatically registered.

Use `TR_HOSTS` to filter the servers queried by bare `tx remote`. Unregistered names are ignored; duplicates are removed. Explicit references bypass the filter:

```bash
TR_HOSTS="dev staging" tx remote
TR_HOSTS="" tx remote              # No available hosts
TR_HOSTS="dev" tx remote @prod     # Select a session on prod
TR_HOSTS="dev" tx remote @prod ls  # Run tmux ls on prod
```

Remote previews and attaching after selection recheck registration. Removing a host while the picker is open prevents subsequent previews and attaching to that host.

Remove one or more registered servers with:

```bash
tx hosts remove dev staging
tx hosts list
```

`tx hosts remove` removes every occurrence of the exact destinations from the allow list, including legacy entries absent from SSH configuration. All names must be registered and syntactically valid; if any name is invalid or unknown, the entire removal fails without changing the file. Removal reads only the allow list and is independent of `TR_HOSTS`. Comments, blank lines, and the order of retained entries are preserved. The file is replaced atomically, with register/remove operations serialized to preserve concurrent changes.

You can also edit the allow-list file directly. It contains one destination per line; blank lines and lines starting with `#` are ignored. The `@` reference prefix belongs to the command line, not to the stored alias.
