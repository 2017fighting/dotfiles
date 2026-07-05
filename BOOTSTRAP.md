# 新机器从零引导（Bootstrap）

> 目标：在一台干净的 macOS / Linux 上，用**一次** `chezmoi init --apply` 把整套环境拉起来。
> 前置脚本 `run_once_before_10` / `run_onchange_before_20` 会自动安装 mise / bitwarden-cli、
> 提示 `bw login` + `bw-ssh-add` 加载 key、clone SSH externals——**无需手动分步操作**。

## 最小手动步骤（仅这 4 步必须人工）

### 1. 放置 age 解密私钥

```sh
mkdir -p ~/.config/chezmoi
cp /path/to/key.txt ~/.config/chezmoi/key.txt
chmod 600 ~/.config/chezmoi/key.txt
```

没有它无法解密 `encrypted_*.age`（含 `~/.ssh/config`、`known_hosts`）。

### 2. 安装 chezmoi（macOS / Linux 通用）

```sh
sh -c "$(curl -fsLS get.chezmoi.io)"
```

### 3.（仅 macOS）安装 Homebrew

这是 `before_10` **唯一无法自满足**的前置——brew 不能自举：

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Linux 跳过（pacman 预装）。

### 4. 一次性 apply（**必须在交互式终端**）

```sh
chezmoi init --apply 2017fighting
```

这一次 apply 会依次完成：

- **`before_10`**：用 brew / pacman 装 `bitwarden-cli` + `mise`；
- **`before_20`**：提前落地 `~/.ssh/config`、`known_hosts`，启动系统 ssh-agent（systemd 单元），**提示你 `bw login`（邮箱 + 主密码 + 2FA）与 `bw-ssh-add`（主密码，把 key 灌进 ssh-agent）**；
- **正常 phase**：写所有配置文件 + clone externals —— SSH 类（oh-my-zsh / nvim / oh-my-tmux）走 ssh-agent 里的 key；HTTPS 类（ecc / catppuccin）不需要 key；
- **`after_*`**：`brew bundle` 还原、pacman 还原、`mise install` 全套运行时、macOS 系统设置、ecc 安装、hapi runner、ssh-agent 单元 enable。

## 为什么这些步骤不能省

- **`bw login` 必须人工**：Bitwarden 主密码从不落盘，**配置文件里没有任何登录凭据**。`data.json` 源只是一个把 macOS 路径重定向到 `~/.config/` 的符号链接，其目标文件在登录之前根本不存在。
- **key 必须先灌进 ssh-agent 才能给 SSH externals 用**：oh-my-zsh / nvim / oh-my-tmux 用 `git@github.com:`，靠 `SSH_AUTH_SOCK` 走系统 ssh-agent。`bw-ssh-add` 从 Bitwarden 取 key 灌进去；vaultwarden 之后挂掉也不影响（key 已在 agent 内存里）。ecc / catppuccin 是 HTTPS，不需要。

## 注意点 / 坑

1. **必须交互式 TTY**。`before_20` 的登录 / 解锁用 `[ -t 0 ]` 守卫；在 CI、管道、或无 TTY 的 ssh 里会**跳过登录解锁**（只打印一句），导致 SSH externals clone 失败。→ 永远从真终端跑。
2. **macOS 漏装 brew 会显式跳过 SSH 链**：看到 `[bootstrap] Homebrew NOT found - SSH bootstrap chain SKIPPED` 的醒目横幅就退出去装 brew，再重跑 apply。
3. **主密码在 `bw-ssh-add` 时输入**：`bw login`（首次）+ `bw-ssh-add`（每次重启后）都会问主密码。key 进 ssh-agent 后一直有效到重启。
4. **首次 apply 偶发某个 SSH external clone 失败就直接重跑**：极少数情况下 `bw-ssh-add` 还没把 key 灌进 agent，首个 SSH clone 就已经开始。整套脚本幂等，确认 `bw-ssh-add` 成功后直接 `chezmoi apply` 再跑即可（`run_once_*` 失败不会标记为已执行）。
5. **init 时会问 name / email / workName / workEmail / sshPubKey**：都有默认值，回车即可（`.chezmoi.yaml.tmpl` 的 `promptStringOnce`）。
6. **`before_20` 现为 `run_onchange_`，不会每次 apply 都跑**：它只在首次（或脚本内容变化时）执行，所以重启后 ssh-agent 里的 key 清空时，后续 `chezmoi apply` 不会自动重新加载——external SSH clone 会失败。手动 `bw-ssh-add` 后重跑 apply 即可。

## apply 之后自检

```sh
just doctor
```

校验 ssh-agent 里有 key + GitHub 能用 key 认证 + SSH externals 已 clone。
