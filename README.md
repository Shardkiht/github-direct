# GitHubDirect

Windows PowerShell 5.1 的 GitHub 主站无代理直连优化器。**v0.1.0 实验版**。

功能：只为 `github.com` 维护一块可识别的 Hosts 记录；启动时和每 30 分钟重新检测，选取经官方范围核验并通过真实 HTTPS 请求的 IPv4。不会改系统 DNS、设置代理、停用证书验证，也不会改 `api.github.com` 等子域名。

> **边界**：GitHub 官方声明 Meta API IP 列表不完整且不建议长期 IP 固定。本工具无法突破全部网络过滤，可能找不到可用 IP；遇到所有候选不可用时保留上次记录并记录失败，不会伪称已经修复。Windows 浏览器、透明代理/TUN、Chrome/Edge 的自带安全 DNS，以及 WSL 内部解析行为可能与 Hosts 不同。具体以实际测试为准。

## 环境

- Windows 10/11、**Windows PowerShell 5.1**、Windows 自带 `curl.exe`
- 安装/卸载需要管理员权限；定时任务以 SYSTEM 身份运行，脚本安装到只有 SYSTEM/管理员可修改的 `%ProgramData%\GitHubDirect`。
- 可以直连 `https://api.github.com/meta`，至少一个 DoH 端点最好可用；脚本禁止使用显式系统代理，但无法控制 VPN/TUN 或透明代理。

## 安装

1. 从 [Releases](https://github.com/Shardkiht/github-direct/releases/latest) 下载 **GitHubDirect-v0.1.0.zip**（不要选 Source code）。
2. 解压，打开里面的 **GitHubDirect** 文件夹。
3. 双击 **安装.cmd**，在 Windows 管理员权限提示中选择“是”。

安装文件会自动申请管理员权限、安装脚本、创建开机和每 30 分钟的刷新任务，并立即运行一次检测。检测可能需要几分钟；完成或失败都会保留窗口，按 Enter 关闭。无需安装 Python、Git 或其他运行环境。若取消权限提示，则不会安装。

请先解压完整文件夹，不要直接在 ZIP 中运行，也不要只复制安装文件。安装完成后可删除解压文件夹；之后自动使用 `%ProgramData%\GitHubDirect` 中的脚本。重复运行安装文件可以更新安装。

高级用法（管理员 Windows PowerShell）：`powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -IntervalMinutes 30`。

## 日常命令

```powershell
$script = "$env:ProgramData\GitHubDirect\github-direct.ps1"
& $script -Mode Status
& $script -Mode DryRun
& $script -Mode Update    # 手动刷新，写 Hosts，需管理员
Get-Content "$env:ProgramData\GitHubDirect\github-direct.log" -Tail 50
schtasks /query /tn GitHubDirect-Refresh /v /fo list
```

## 卸载与恢复

双击解压文件夹内的 **卸载.cmd**，确认管理员权限即可删除计划任务并恢复本工具修改的 Hosts 区块，默认保留备份和日志。也可使用管理员 PowerShell：

```powershell
.\uninstall.ps1             # 删除任务，移除仅属于本工具的 Hosts 区块，保留备份日志
.\uninstall.ps1 -RemoveLogs # 额外删除日志和备份
```

## 安全策略

1. 候选取自 TLS 验证过的 DNS-over-HTTPS 响应，以及 GitHub `https://api.github.com/meta` 的 `web` 字段中的独立 `/32` 地址。
2. 仅允许位于 GitHub 官方 `web` CIDR 范围内的 IPv4 参与测速。
3. 使用 `curl.exe --resolve` 直接连目标 IP，仍以 `github.com` 做 SNI/HTTP Host/正常证书链验证。不使用 `-k` 或第三方代理。
4. 默认两个真实 HTTPS GET 均成功（HTTP 200、301 或 302）才会采用；仍健康且慢于最快不超过 25% 时保留原 IP，避免频繁切换。
5. 若 Meta API 不可达，不修改 Hosts；没有健康候选时保留上次成功映射并记录失败。**旧 IP 可能随时间失效**，此时可手动执行 `-Mode Restore` 切回系统 DNS。
6. 不修改原有非本工具的 `github.com` Hosts 项；检测到冲突就拒绝覆盖。更新 Hosts 前备份到 ProgramData，失败时尝试回滚。
7. 不自动下载或执行网络上的脚本，不收集 Token、账号或仓库内容。

## 范围与限制

- 只影响使用 Windows 系统 Hosts 解析的 `github.com` 网站；浏览器的一些 DNS/代理特性可能绕开。
- 不能确保 SSH Push/Pull 更稳定：Git 可通过 GitHub 官方 SSH 443 独立配置（`ssh.github.com:443`）。
- `raw.githubusercontent.com`、Release 下载、Git LFS 等子域名不在 v0.1 范围；GitHub Meta 列表也可能不完整。
- 每次检查最多默认 12 个候选，每个两次请求，可能花费较长时间；太频繁没有意义。
- 这是兼容 PowerShell 5.1 的初版，**尚未在实际 Windows 电脑上完成端到端验收**；已通过离线语法与安装包检查，真实提权安装、任务调度和网络检测尚未验收。可在安装前运行 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\src\github-direct.ps1 -Mode DryRun`，并在安装后审阅日志。

## 参考文档

- [GitHub 官方 IP 地址说明](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/about-githubs-ip-addresses)
- [GitHub Meta API](https://api.github.com/meta)
- [Cloudflare DNS over HTTPS](https://developers.cloudflare.com/1.1.1.1/encryption/dns-over-https/make-api-requests/)
- [Microsoft Schtasks](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/schtasks-create)
