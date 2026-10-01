# tr

Use tmux commands as usual. Add `-H <host>` before the subcommand to run them over SSH.

| Command | Usage |
| --- | --- |
| `tr` | Select a local or remote session with a pane preview (requires fzf) |
| `tr register <host> [host ...]` | Add remote servers to the persistent allow list |
| `tr <command> ...` | Run a tmux command locally |
| `tr -H <host> <command> ...` | Run a tmux command on a registered SSH host |
| `tr -H all ls` | List sessions across this machine and registered SSH hosts |
| `tr --help` | Show help |

## Installation

Requires Bash 3.2+ and tmux. Remote commands also require SSH and tmux on the remote host. Install fzf to use the interactive session selector.

```bash
git clone https://github.com/ryqdev/tmuxer.git
cd tmuxer
./install.sh
export PATH="$HOME/.local/bin:$PATH"
tr --help
```

The installer copies `tr` to `~/.local/bin/tr`. Add the `export PATH` line to your shell configuration (such as `~/.zshrc` or `~/.bashrc`) to make it permanent.

Set `PREFIX` to change the installation directory; the command is installed in `$PREFIX/bin`. Set `NAME` to change the command name. For example, to avoid shadowing the system `tr` command:

```bash
NAME=tx ./install.sh
```

Use `tx` in place of `tr` in the examples below if you choose that name.

## Examples

```bash
# Local sessions
tr new-session -s work
tr attach -t '=work'

# Remote sessions
tr register dev
tr -H dev new-session -s work
tr -H dev attach -t '=work'
tr -H dev kill-session -t '=work'

# Send input and capture pane output
tr -H dev send-keys -t '=work:' 'echo hello' Enter
tr -H dev capture-pane -p -t '=work:' > pane.txt

# Custom sockets
tr -L project ls
tr -H dev -S /path/to/socket ls
tr -H all -L project ls
```

## Hosts

Register remote servers before using them:

```bash
tr register dev staging prod
tr register user@192.0.2.10
tr -H all ls
tr
```

`tr register` saves each server in `${XDG_CONFIG_HOME:-$HOME/.config}/tmuxer/hosts` (normally `~/.config/tmuxer/hosts`). It accepts SSH aliases, hostnames, IPv4/IPv6 addresses, and `user@host` destinations. Registration does not connect to the server, and registering the same server again does not add duplicates. Wildcards, whitespace, and the reserved name `all` are rejected.

Only registered servers are scanned by `tr` and `tr -H all ls`. Local sessions are always included. An absent or empty allow list means local sessions only. Explicit `tr -H <host>` commands also require the exact destination to be registered; `dev` and `user@dev` are separate entries.

SSH still uses your normal configuration to connect to registered aliases, but entries in `~/.ssh/config` are not automatically registered. Existing users must run `tr register` for the servers they want to keep discovering.

Use `TR_HOSTS` to scan a subset of the allow list. Unregistered names in this variable are ignored:

```bash
TR_HOSTS="dev staging" tr
TR_HOSTS="" tr                 # Local sessions only
```

To remove a server, delete its line from the allow-list file. The file contains one destination per line; blank lines and lines starting with `#` are ignored.
