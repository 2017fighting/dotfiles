# 使用chezmoi管理dotfiles

## 适用场景

- 同步这三方的配置：家里mac、工作mac、工作测试用服务器linux

## 依赖

- 科学上网的网络环境
- chezmoi
- homebrew(mac限定)
- Bitwarden app(mac限定)

## 恢复流程

新机器的完整引导步骤（含 mise/bwssh 自动化与坑）见 **[BOOTSTRAP.md](./BOOTSTRAP.md)**。

简要来说只需 4 步：放好 `~/.config/chezmoi/key.txt` → 安装 chezmoi →（mac）安装 Homebrew → `chezmoi init --apply 2017fighting`。`run_before_10` / `run_before_20` 会自动完成 mise / bitwarden-cli / bwssh 的安装、bwssh 启动与登录解锁、以及 SSH externals（oh-my-zsh、nvim、oh-my-tmux）的 clone。

apply 完成后可用 `just doctor` 自检 SSH/bwssh 链路是否就绪。

## 特殊文件/文件夹
>
> <https://www.chezmoi.io/reference/special-files/>

- `.chezmoi.yaml.tmpl`: 用于生成配置文件`chezmoi.toml`，在`init`时生成，无法引用chezmoidata数据
- `.chezmoiignore`: 定义了哪些文件不需要复制到home目录，例如本文件`README.md`就不需要复制到home目录，可以添加到这个文件里
- `.chezmoidata`: 目录下的文件用来定义数据，可以用在模版里
- `.chezmoitemplates`: 目录下的文件是定义模版，可以用在其他tmpl文件里，用法`{{ template "foo" . }}`会引用`.chezmoitemplates/foo`文件
- `.chezmoiexternals`: 可以引用外部源，例如其他github仓库
- `.chezmoiscripts`: 定义一些脚本，可以在`apply`前后执行

## 脚本执行逻辑
>
> <https://www.chezmoi.io/user-guide/use-scripts-to-perform-actions/>

### 命名方式

`{是否执行}[{执行时机}][{自定义字符串}]`

### 是否执行

- `run_`: 每次apply都执行
- `run_onchange_`: 只有脚本内容变化才会执行(相同内容的脚本只会执行一次，会记录历史)
- `run_once_`: 每个机器上只会执行一次，如果是tmpl文件还是会计算hash判断是否变化的

### 执行时机

- 缺省: apply`中`执行，例如`run_b.sh`会在更新完`a.txt`之后、更新`c.txt`之前执行
- `before_`: apply之`前`执行，多个脚本之间也是按照字母顺序执行的
- `after_`: apply之`后`执行，多个脚本之间也是按照字母顺序执行的

## 管理方式

- chezmoi 管理文件
- age加密解密敏感文件，密钥存其他地方
- brew bundle 管理软件包，每次新加软件包后，都要执行一下`brew bundle dump --force --file="~/Brewfile"`
- ?管理系统设置
