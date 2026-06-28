# 新机器从零引导（Bootstrap）

> 目标：在一台干净的 macOS / Linux 上，用**一次** `chezmoi init --apply` 把整套环境拉起来。
> 前置脚本 `run_once_before_10` / `run_onchange_before_20` 会自动安装 mise / bw / bwssh、启动 bwssh、
> 提示登录解锁、clone SSH externals——**无需手动分步操作**。

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

- **`before_10`**：用 brew / pacman 装 `bitwarden-cli` + `mise`，再用 mise 装 `python` + `pipx:bwssh`；
- **`before_20`**：提前落地 `~/.config/bwssh/config.toml`、`~/.ssh/config`、`known_hosts`，启动 bwssh，**提示你 `bw login`（邮箱 + 主密码 + 2FA）与 `bwssh unlock`（主密码）**；
- **正常 phase**：写所有配置文件 + clone externals —— SSH 类（oh-my-zsh / nvim / oh-my-tmux）走 bwssh 提供的 key；HTTPS 类（ecc / catppuccin）不走 bwssh；
- **`after_*`**：`brew bundle` 还原、pacman 还原、`mise install` 全套运行时、macOS 系统设置、ecc 安装、hapi runner、bwssh LaunchAgent。

## 为什么这些步骤不能省

- **`bw login` 必须人工**：Bitwarden 主密码从不落盘，**配置文件里没有任何登录凭据**。`data.json` 源只是一个把 macOS 路径重定向到 `~/.config/` 的符号链接，其目标文件在登录之前根本不存在。
- **bwssh 提供的 key 是给 SSH externals 用的**：oh-my-zsh / nvim / oh-my-tmux 用 `git@github.com:`，必须靠 `~/.ssh/config` 里的 `IdentityAgent` 走 bwssh。ecc / catppuccin 是 HTTPS，不需要。

## 注意点 / 坑

1. **必须交互式 TTY**。`before_20` 的登录 / 解锁用 `[ -t 0 ]` 守卫；在 CI、管道、或无 TTY 的 ssh 里会**跳过登录解锁**（只打印一句），导致 SSH externals clone 失败。→ 永远从真终端跑。
2. **macOS 漏装 brew 会显式跳过 SSH 链**：看到 `[bootstrap] Homebrew NOT found - SSH bootstrap chain SKIPPED` 的醒目横幅就退出去装 brew，再重跑 apply。
3. **主密码可能被问两次**：`bw login` 之后 bwssh 有独立的 session，可能再 `bwssh unlock` 一次。提前备好主密码。
4. **首次 apply 偶发某个 SSH external clone 失败就直接重跑**：bwssh 就绪轮询已砍到 5 次，极少数情况下首个 SSH clone 会与 daemon 就绪竞态。整套脚本幂等，直接 `chezmoi apply` 再跑即可（`run_once_*` 失败不会标记为已执行）。
5. **init 时会问 name / email / workName / workEmail / sshPubKey**：都有默认值，回车即可（`.chezmoi.yaml.tmpl` 的 `promptStringOnce`）。
6. **`before_20` 现为 `run_onchange_`，不会每次 apply 都跑**：它只在首次（或脚本内容变化时）执行，所以 bwssh daemon 挂掉 / vault 重新锁定后，后续 `chezmoi apply` 不会自动恢复——external SSH clone 会失败。手动 `bwssh start && bwssh unlock` 后重跑 apply 即可。

## apply 之后自检

```sh
just doctor
```

校验 bwssh 守护进程存活 + vault 解锁 + GitHub 能用 key 认证 + SSH externals 已 clone。
