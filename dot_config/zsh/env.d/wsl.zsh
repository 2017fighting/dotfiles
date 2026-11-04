# xdg-open will use this
export BROWSER=wslview

# wslview 默认会先 `curl --head --silent -g "<url>"`（无 --max-time）判断是不是链接。
# 变量名是反的：wslview:470 `skip_validation_check=${WSLVIEW_SKIP_VALIDATION_CHECK:-1}`,
# 只有 0 才跳过校验（默认 1 = 仍然校验）。
# 后果：URL 指向本机尚未就绪的服务时 curl 会一直挂着（mitmweb 自己的 8081 就是，
# 而 mitmweb 又正阻塞在 wait(wslview) 上 ⇒ 互等），叠加 WSL interop 每次 10s 超时
# ⇒ 一次 wslview 卡 30-75s。设 0 = 不做探测，直接把 URL 交给 Windows 打开。
#
# ⚠ wslu 4.1.10 的 /usr/share/wslu/conf 会硬赋值 WSLVIEW_SKIP_VALIDATION_CHECK=1，
#   且在该文件被 source 之后才读 ⇒ 单靠这个 export 是死代码。真正生效的是
#   /usr/share/wslu/custom.conf（官方覆盖层，在 conf 之后 source，包里不跟踪）。
#   两处都保留：custom.conf 保当前机器，这一行保其他机器/上游修正后的版本。
export WSLVIEW_SKIP_VALIDATION_CHECK=0
