# tx

Use `tx` like local tmux. Remote host management, SSH commands, and the cross-host session selector live under `tx remote`.

| Command | Usage |
| --- | --- |
| `tx` | Run local tmux's default command (normally create and attach to a new session) |
| `tx <command> ...` | Run a tmux command locally |
| `tx remote` | Select a local or remote session with a pane preview (requires fzf) |
| `tx remote list` | List all registered remote servers without connecting |
| `tx remote register <host> [host ...]` | Add remote servers to the persistent allow list |
| `tx remote -H <host> [tmux arguments...]` | Run tmux on a registered SSH host |
| `tx remote -H all ls` | List sessions across this machine and registered SSH hosts |
| `tx remote --help` | Show remote command help |
| `tx --help` | Show help |

Except for `tx --help` and the `remote` namespace, arguments are passed unchanged to local tmux. Local commands do not read the remote allow list or require SSH or fzf.

## Installation

Requires Bash 3.2+ and tmux. Remote execution also requires SSH and tmux on the remote host. Install fzf to use the `tx remote` interactive session selector. Host registration and listing do not require tmux, SSH, or fzf.

```bash
git clone https://github.com/ryqdev/tmuxer.git
cd tmuxer
./install.sh
export PATH="$HOME/.local/bin:$PATH"
tx --help
```

The installer copies `tx` to `~/.local/bin/tx`. Add the `export PATH` line to your shell configuration (such as `~/.zshrc` or `~/.bashrc`) to make it permanent.

Set `PREFIX` to change the installation directory; the command is installed in `$PREFIX/bin`. Set `NAME` to change the command name:

```bash
NAME=tm ./install.sh
```

Use your chosen name in place of `tx` in the examples below. Avoid `NAME=tr`: it shadows the system text-processing command used by shell scripts, including NVM.

### Upgrading from tr

Older versions installed the wrapper as `tr`, which can cause `unknown command: t` during shell startup. If `~/.local/bin/tr` is the old tmuxer wrapper, move it aside before installing `tx`:

```bash
mv "$HOME/.local/bin/tr" "$HOME/.local/bin/tr-tmux-backup"
./install.sh
hash -r
```

For a custom `PREFIX`, move the old wrapper from `$PREFIX/bin/tr` instead. Update any tmuxer aliases or scripts to call `tx`. The `TR_HOSTS` environment variable is still supported.

### Upgrading to the remote namespace

Existing allow-list files continue to work. Update commands and scripts as follows:

| Previous command | New command |
| --- | --- |
| `tx` (session selector) | `tx remote` |
| `tx register dev` | `tx remote register dev` |
| `tx -H dev ls` | `tx remote -H dev ls` |
| `tx -H all ls` | `tx remote -H all ls` |

The old top-level `register` and `-H` forms are no longer wrapper commands; they are passed to local tmux. Bare `tx` now uses local tmux's default command.

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
tx remote -H dev new-session -s work
tx remote -H dev attach -t '=work'
tx remote -H dev kill-session -t '=work'

# Send input and capture pane output
tx remote -H dev send-keys -t '=work:' 'echo hello' Enter
tx remote -H dev capture-pane -p -t '=work:' > pane.txt

# Custom sockets
tx -L project ls
tx remote -H dev -S /path/to/socket ls
tx remote -H all -L project ls
```

Put `-H <host>` and tmux global options before the tmux subcommand, after `remote`. With no tmux arguments, `tx remote -H dev` runs the remote tmux default command. `-H all` only supports `ls`, without subcommand arguments; tmux global options such as `-L` and `-S` are allowed.

## Hosts

Register remote servers before using them:

```bash
tx remote register dev staging prod
tx remote register user@192.0.2.10
tx remote list
tx remote -H all ls
tx remote
```

`tx remote register` saves each server in `${XDG_CONFIG_HOME:-$HOME/.config}/tmuxer/hosts` (normally `~/.config/tmuxer/hosts`). It accepts SSH aliases, hostnames, IPv4/IPv6 addresses, and `user@host` destinations. Registration does not connect to the server, and registering the same server again does not add duplicates. Wildcards, whitespace, and the reserved name `all` are rejected.

`tx remote list` prints every registered destination once, in registration order, with one destination per line. It does not connect to servers and is not filtered by `TR_HOSTS`. An absent or empty allow list produces no output.

Only registered servers are scanned by `tx remote` and `tx remote -H all ls`. Local sessions are always included. An absent or empty allow list means local sessions only. Explicit `tx remote -H <host>` commands also require the exact destination to be registered; `dev` and `user@dev` are separate entries.

SSH still uses your normal configuration to connect to registered aliases, but entries in `~/.ssh/config` are not automatically registered. Run `tx remote register` for the servers you want to discover.

Use `TR_HOSTS` to scan a subset of the allow list. Unregistered names in this variable are ignored:

```bash
TR_HOSTS="dev staging" tx remote
TR_HOSTS="" tx remote                 # Local sessions only
TR_HOSTS="dev staging" tx remote -H all ls
```

Discovery uses noninteractive SSH and skips hosts that cannot connect, require a password prompt, or have no sessions. The interactive selector shows host, session name, window count, and attached/detached state with a pane preview. Selecting a local session switches clients if already inside tmux, or attaches otherwise; selecting a remote session attaches over SSH.

To remove a server, delete its line from the allow-list file. The file contains one destination per line; blank lines and lines starting with `#` are ignored.
