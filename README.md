# tr

Use tmux commands as usual. Add `-H <host>` before the subcommand to run them over SSH.

| Command | Usage |
| --- | --- |
| `tr` | Select a local or remote session with a pane preview (requires fzf) |
| `tr <command> ...` | Run a tmux command locally |
| `tr -H <host> <command> ...` | Run a tmux command on an SSH host |
| `tr -H all ls` | List sessions across this machine and all SSH hosts |
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

Hosts are read from `~/.ssh/config`, excluding wildcard entries. Override the list with `TR_HOSTS`:

```bash
TR_HOSTS="dev staging prod" tr
TR_HOSTS="" tr                  # Local sessions only
```
