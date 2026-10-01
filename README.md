# tx

Use tmux commands as usual. Add `-H <host>` before the subcommand to run them over SSH.

| Command | Usage |
| --- | --- |
| `tx` | Select a local or remote session with a pane preview (requires fzf) |
| `tx register <host> [host ...]` | Add remote servers to the persistent allow list |
| `tx <command> ...` | Run a tmux command locally |
| `tx -H <host> <command> ...` | Run a tmux command on a registered SSH host |
| `tx -H all ls` | List sessions across this machine and registered SSH hosts |
| `tx --help` | Show help |

## Installation

Requires Bash 3.2+ and tmux. Remote commands also require SSH and tmux on the remote host. Install fzf to use the interactive session selector.

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

## Examples

```bash
# Local sessions
tx new-session -s work
tx attach -t '=work'

# Remote sessions
tx register dev
tx -H dev new-session -s work
tx -H dev attach -t '=work'
tx -H dev kill-session -t '=work'

# Send input and capture pane output
tx -H dev send-keys -t '=work:' 'echo hello' Enter
tx -H dev capture-pane -p -t '=work:' > pane.txt

# Custom sockets
tx -L project ls
tx -H dev -S /path/to/socket ls
tx -H all -L project ls
```

## Hosts

Register remote servers before using them:

```bash
tx register dev staging prod
tx register user@192.0.2.10
tx -H all ls
tx
```

`tx register` saves each server in `${XDG_CONFIG_HOME:-$HOME/.config}/tmuxer/hosts` (normally `~/.config/tmuxer/hosts`). It accepts SSH aliases, hostnames, IPv4/IPv6 addresses, and `user@host` destinations. Registration does not connect to the server, and registering the same server again does not add duplicates. Wildcards, whitespace, and the reserved name `all` are rejected.

Only registered servers are scanned by `tx` and `tx -H all ls`. Local sessions are always included. An absent or empty allow list means local sessions only. Explicit `tx -H <host>` commands also require the exact destination to be registered; `dev` and `user@dev` are separate entries.

SSH still uses your normal configuration to connect to registered aliases, but entries in `~/.ssh/config` are not automatically registered. Existing users must run `tx register` for the servers they want to keep discovering.

Use `TR_HOSTS` to scan a subset of the allow list. Unregistered names in this variable are ignored:

```bash
TR_HOSTS="dev staging" tx
TR_HOSTS="" tx                 # Local sessions only
```

To remove a server, delete its line from the allow-list file. The file contains one destination per line; blank lines and lines starting with `#` are ignored.
