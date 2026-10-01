# tr

Use tmux commands as usual. Add `-H <host>` before the subcommand to run them over SSH.

| Command | Usage |
| --- | --- |
| `tr` | Select a local or remote session with a pane preview (requires fzf) |
| `tr <command> ...` | Run a tmux command locally |
| `tr -H <host> <command> ...` | Run a tmux command on an SSH host |
| `tr -H all ls` | List sessions across this machine and all SSH hosts |
| `tr --help` | Show help |

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
