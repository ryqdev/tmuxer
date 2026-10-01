# tx

Use tmux commands as usual. Add `-H <host>` before the subcommand to run them over SSH.

| Command | Usage |
| --- | --- |
| `tx` | Select a local or remote session with a pane preview (requires fzf) |
| `tx <command> ...` | Run a tmux command locally |
| `tx -H <host> <command> ...` | Run a tmux command on an SSH host |
| `tx -H all ls` | List sessions across this machine and all SSH hosts |
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

Hosts are read from `~/.ssh/config`, excluding wildcard entries. Override the list with `TR_HOSTS`:

```bash
TR_HOSTS="dev staging prod" tx
TR_HOSTS="" tx                  # Local sessions only
```
