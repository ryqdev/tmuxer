# tr

用系统 ssh 管理本机和远程服务器的 tmux。单文件 Bash 脚本，兼容 macOS 自带的 Bash 3.2 和常见 Linux；服务器不需要安装 agent。

本机执行需要 tmux，远程执行需要本机 ssh 和服务器上的 tmux。交互选择额外需要本机 fzf。扫描使用 awk 和系统自带的 mktemp、rm，不依赖 column，也不需要 Python、Node 或 SSH 库。

## 安装

```bash
git clone https://github.com/ryqdev/tmuxer.git
cd tmuxer
./install.sh                     # ~/.local/bin/tr
NAME=tx ./install.sh             # ~/.local/bin/tx（推荐）
PREFIX=/usr/local NAME=rt ./install.sh  # /usr/local/bin/rt，需要相应写权限
export PATH="$HOME/.local/bin:$PATH"
```

也可以直接运行当前目录的 `./tr`。以下示例使用默认名称，改名安装后相应替换成 tx 或 rt。

## 命名冲突警告

**`tr` 与系统自带的字符转换命令 tr 重名。** 如果安装目录在 PATH 里排在 `/usr/bin` 之前，会遮蔽系统命令，并可能影响其他脚本。建议使用 `NAME=tx ./install.sh` 或 `NAME=rt ./install.sh` 安装；需要系统命令时可明确调用 `/usr/bin/tr`。本工具内部不会调用系统 tr。

## 用法

| tmux 命令 | 本机 tr 命令 | 远程 tr 命令 |
| --- | --- | --- |
| `tmux ls` | `tr ls` | `tr -H dev ls` |
| `tmux new-session -s work` | `tr new-session -s work` | `tr -H dev new-session -s work` |
| `tmux attach -t '=work'` | `tr attach -t '=work'` | `tr -H dev attach -t '=work'` |
| `tmux send-keys -t '=work:' 'echo hello' Enter` | `tr send-keys -t '=work:' 'echo hello' Enter` | `tr -H dev send-keys -t '=work:' 'echo hello' Enter` |
| `tmux capture-pane -p -t '=work:'` | `tr capture-pane -p -t '=work:'` | `tr -H dev capture-pane -p -t '=work:'` |
| `tmux kill-session -t '=work'` | `tr kill-session -t '=work'` | `tr -H dev kill-session -t '=work'` |
| `tmux -L project ls` | `tr -L project ls` | `tr -H dev -L project ls` |

`-H` 放在 tmux 子命令之前，允许放在 tmux 全局选项之间。其余参数保持原样，包括空参数、空格和引号；远程参数逐个用 POSIX shell 单引号转义。`tr --help` 显示帮助。

与 tmux 的两处行为差异：

1. **无参数 `tr`**：并行扫描本机和 SSH 主机，用 fzf 选择 session，右侧预览当前 pane 的最近 100 行。选中本机 session 时，已在 tmux 内就 `switch-client`，否则 `attach`；远程使用 `ssh -t` 加 `attach -t '=session名'` 精确匹配。取消后退出，没有 session 时返回 1。
2. **`tr -H all ls`**：列出本机和所有主机的 session。输出用制表符分隔，包含 `HOST / SESSION / WINDOWS / STATE`，本机标记为 `[local]`，状态为 attached 或 detached。`-H all` 只支持 `ls`，可在子命令前带全局选项，例如 `tr -H all -L project ls`。

其他命令直接执行本机 tmux 或系统 ssh。仅当 stdin 是终端，且子命令是 `attach`、`attach-session`、`a`、`at`、`new`、`new-session` 或没有子命令时，直接远程调用才使用 `ssh -t`。其他调用使用 `ssh -T`，因此输出可以接管道：

```bash
tr -H dev capture-pane -p -t '=work:' > pane.txt
tr -H dev send-keys -t '=work:' "python x.py --a 'b c'" Enter
```

## 主机列表与 SSH 配置

默认从 `~/.ssh/config` 的 Host 条目收集别名，支持一行多个别名、注释、去重，以及 Include 的通配路径、嵌套文件和带空格的路径。相对 Include 路径以 `~/.ssh` 为基准；循环引用不会无限读取。含通配符、否定模式的 Host 条目不作为主机枚举。解析只用于收集别名，不执行 Match exec；实际连接配置由系统 ssh 处理。

```bash
TR_HOSTS="dev staging prod" tr    # 覆盖配置里的主机列表并去重
TR_HOSTS="" tr                   # 只扫描本机
tr -H 192.0.2.10 ls              # 显式指定主机，无须出现在列表里
```

建议启用连接复用（把下面的通用配置放在具体 Host 配置之后）：

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

工具自然继承 SSH 别名、ProxyJump、ControlMaster 和 ssh-agent。扫描及远程预览设置 `BatchMode=yes`、`ConnectTimeout=3` 和 `ConnectionAttempts=1`；连接失败、需要密码、没有 tmux 或没有 session 的主机会被跳过。直接 `tr -H dev ...` 的认证方式仍由 ssh 决定。

## 常见问题

- **主机不出现在列表**：列表展示 session，不展示空主机。确认别名是字面量 Host 条目，TR_HOSTS 没有覆盖它；先手动 `ssh dev` 完成主机指纹确认、配置密钥或 ssh-agent，再执行 `tr -H dev ls` 检查 tmux。需要密码、连接超时、tmux 不在远程 PATH 或没有 session 都会让扫描跳过该主机。Include 收集的是声明过的别名，是否能连接仍取决于 ssh 的条件配置。
- **嵌套 tmux 前缀键冲突**：本地 tmux 内进入远程 tmux 会形成嵌套。默认前缀是 `Ctrl-b`，按 `Ctrl-b Ctrl-b` 可向内层发送一次前缀，再按目标按键；也可以给内外层配置不同的 prefix。
- **自定义 socket**：用 `tr -L project ls` 或 `tr -S /path/to/socket ls`；远程用 `tr -H dev -L project ls`。`-S` 路径在目标主机上解释。汇总可使用 `tr -H all -L project ls`；无参数选择器扫描各主机的默认 socket，本机遵循 TMUX/TMUX_TMPDIR 环境。要进入其他 socket 的 session，请显式使用对应选项和 attach。
- **缺少 fzf 或 column**：fzf 只用于无参数选择；显式命令和汇总不需要它。列表直接按制表符分列，不调用 column。

## 测试

```bash
bash -n tr install.sh tests/run.sh tests/mocks/*
bash tests/run.sh
# macOS 上可以明确验证自带版本：
TEST_BASH=/bin/bash /bin/bash tests/run.sh
# 如果安装了 shellcheck：
shellcheck --severity=error tr install.sh tests/run.sh tests/mocks/*
```

测试不依赖 bats，使用系统的 script(1) 生成终端，必须有本机 tmux；真实 tmux 用 `/tmp` 下的临时 TMUX_TMPDIR 和独立 `-L` / `-S` socket，以免 UNIX socket 路径超过长度限制，也不触碰已有服务器。

模拟 ssh 和 fzf 覆盖参数引号、空参数和换行、TTY/非 TTY、全局选项、错误输入、Include 和 TR_HOSTS、并行扫描、汇总输出、选择器调用、预览和临时目录清理。真实本机 tmux 覆盖创建、列出、send-keys、capture-pane、kill-session 及两个 socket 选项。模拟不会验证实际 SSH 网络、认证、ProxyJump、ControlMaster 或真实 fzf 界面的操作体验。

## 协议

[MIT License](LICENSE)，Copyright (c) 2026 ryqdev。
