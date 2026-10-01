# tx

Use `tx` like local tmux. Remote host management, SSH commands, and the cross-host session selector live under `tx remote`.

tx operations use named subcommands and positional arguments. tmux's own arguments, such as `-s`, `-t`, `-L`, and `-S`, are passed through unchanged.

| Command | Usage |
| --- | --- |
| `tx` | Run local tmux's default command (normally create and attach to a new session) |
| `tx <command> ...` | Run a tmux command locally |
| `tx remote select` | Select a local or remote session with a pane preview (requires fzf) |
| `tx remote list` | List all registered remote servers without connecting |
| `tx remote candidates` | List SSH aliases from your SSH config that can be registered |
| `tx remote register <host> [host ...]` | Add remote servers to the persistent allow list |
| `tx remote exec <host> [tmux arguments...]` | Run tmux on a registered SSH host |
| `tx remote sessions [tmux global options...]` | List sessions across this machine and registered SSH hosts |
| `tx remote help` | Show remote command help |
| `tx help` | Show help |

Bare `tx remote` is also supported as shorthand for `tx remote select`. Except for the `help` and `remote` subcommands, arguments are passed unchanged to local tmux. Local commands do not read the remote allow list or require SSH or fzf.

## Installation

Requires Bash 3.2+ and tmux. Remote execution also requires SSH and tmux on the remote host. Install fzf to use the `tx remote select` interactive session selector. Host registration and listing do not require tmux, SSH, or fzf. Listing SSH candidates additionally uses awk.

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

Tab completes `tx remote can` to `tx remote candidates`, all other remote subcommands, SSH aliases after `remote register`, and registered hosts after `remote exec`. Host completion reads local configuration without connecting over SSH. Local tmux commands reuse Zsh's tmux completion.

### Upgrading from tr

Older versions installed the wrapper as `tr`, which can cause `unknown command: t` during shell startup. If `~/.local/bin/tr` is the old tmuxer wrapper, move it aside before installing `tx`:

```bash
mv "$HOME/.local/bin/tr" "$HOME/.local/bin/tr-tmux-backup"
./install.sh
hash -r
```

For a custom `PREFIX`, move the old wrapper from `$PREFIX/bin/tr` instead. Update any tmuxer aliases or scripts to call `tx`. The `TR_HOSTS` environment variable is still supported.

### Upgrading remote commands

Existing allow-list files continue to work. Update commands and scripts as follows:

| Previous command | New command |
| --- | --- |
| `tx` (session selector) | `tx remote select` |
| `tx register dev` | `tx remote register dev` |
| `tx -H dev ls` or `tx remote -H dev ls` | `tx remote exec dev ls` |
| `tx -H all ls` or `tx remote -H all ls` | `tx remote sessions` |
| `tx remote -H all -L project ls` | `tx remote sessions -L project` |
| `tx --help` | `tx help` |
| `tx remote --help` | `tx remote help` |

The old top-level `register`, `-H`, and `--help` forms are passed to local tmux. `tx remote -H ...` and `tx remote --help` are rejected with a pointer to `tx remote help`. Bare `tx` uses local tmux's default command.

## Examples

```bash
# Local sessions
tx
tx ls
tx new-session -s work
tx attach -t '=work'

# Remote sessions
tx remote register dev
tx remote list
tx remote exec dev new-session -s work
tx remote exec dev attach -t '=work'
tx remote exec dev kill-session -t '=work'

# Send input and capture pane output
tx remote exec dev send-keys -t '=work:' 'echo hello' Enter
tx remote exec dev capture-pane -p -t '=work:' > pane.txt

# Custom sockets
tx -L project ls
tx remote exec dev -S /path/to/socket ls
tx remote sessions -L project
```

The host is the positional argument immediately after `exec`. Everything after the host is passed unchanged to tmux, with tmux global options before the tmux subcommand. With no tmux arguments, `tx remote exec dev` runs the remote tmux default command.

`tx remote sessions` performs session discovery directly. It accepts tmux global options such as `-L` and `-S` to choose a socket, without a tmux subcommand or subcommand arguments. It does not execute arbitrary commands across hosts.

## Hosts

Find server aliases in your SSH configuration before registering them:

```bash
tx remote candidates
# dev
# staging
tx remote register dev staging
```

`tx remote candidates` reads concrete `Host` aliases from `~/.ssh/config`, including nested `Include` files. It prints each alias once, in configuration order, with one alias per line. Wildcard and negated patterns, the reserved name `all`, and names rejected by `remote register` are skipped. It lists aliases whether or not they are already registered, independently of `TR_HOSTS` and the allow-list file. A missing or empty SSH config produces no output.

Include paths support absolute paths, paths relative to `~/.ssh`, `~/` paths, double quotes, and globs in lexical order. Repeated files and include cycles are skipped. Dynamic paths using SSH tokens, environment variables, or other users' `~user` paths are not expanded. This is a list of configured candidates: it does not evaluate `Host`/`Match` conditions, execute `Match exec` commands, connect to servers, or change the allow list. Use `tx remote register` to add the aliases you choose.

Register remote servers before using them:

```bash
tx remote register dev staging prod
tx remote register user@192.0.2.10
tx remote list
tx remote sessions
tx remote select
```

`tx remote register` saves each server in `${XDG_CONFIG_HOME:-$HOME/.config}/tmuxer/hosts` (normally `~/.config/tmuxer/hosts`). It accepts SSH aliases, hostnames, IPv4/IPv6 addresses, and `user@host` destinations. Registration does not connect to the server, and registering the same server again does not add duplicates. Wildcards, whitespace, and the reserved name `all` are rejected.

`tx remote list` prints every registered destination once, in registration order, with one destination per line. It does not connect to servers and is not filtered by `TR_HOSTS`. An absent or empty allow list produces no output.

Only registered servers are scanned by `tx remote select` and `tx remote sessions`. Local sessions are always included. An absent or empty allow list means local sessions only. `tx remote exec <host>` also requires the exact destination to be registered; `dev` and `user@dev` are separate entries.

SSH still uses your normal configuration to connect to registered aliases, but entries in `~/.ssh/config` are not automatically registered. Run `tx remote register` for the servers you want to discover.

Use `TR_HOSTS` to scan a subset of the allow list. Unregistered names in this variable are ignored:

```bash
TR_HOSTS="dev staging" tx remote select
TR_HOSTS="" tx remote select                 # Local sessions only
TR_HOSTS="dev staging" tx remote sessions
```

Discovery uses noninteractive SSH and skips hosts that cannot connect, require a password prompt, or have no sessions. The interactive selector shows host, session name, window count, and attached/detached state with a pane preview. Selecting a local session switches clients if already inside tmux, or attaches otherwise; selecting a remote session attaches over SSH.

To remove a server, delete its line from the allow-list file. The file contains one destination per line; blank lines and lines starting with `#` are ignored.
