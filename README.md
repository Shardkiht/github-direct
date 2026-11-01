# GitHubDirect

Windows PowerShell 5.1 的 GitHub 主站无代理直连优化器。**v0.1.0 实验版**。

功能：只为 `github.com` 维护一块可识别的 Hosts 记录；启动时和每 30 分钟重新检测，选取经官方范围核验并通过真实 HTTPS 请求的 IPv4。不会改系统 DNS、设置代理、停用证书验证，也不会改 `api.github.com` 等子域名。

> **边界**：GitHub 官方声明 Meta API IP 列表不完整且不建议长期 IP 固定。本工具无法突破全部网络过滤，可能找不到可用 IP；遇到所有候选不可用时保留上次记录并记录失败，不会伪称已经修复。Windows 浏览器、透明代理/TUN、Chrome/Edge 的自带安全 DNS，以及 WSL 内部解析行为可能与 Hosts 不同。具体以实际测试为准。

## 环境

- Windows 10/11、**Windows PowerShell 5.1**、Windows 自带 `curl.exe`
- 安装/卸载需要管理员权限；定时任务以 SYSTEM 身份运行，脚本安装到只有 SYSTEM/管理员可修改的 `%ProgramData%\GitHubDirect`。
- 可以直连 `https://api.github.com/meta`，至少一个 DoH 端点最好可用；脚本禁止使用显式系统代理，但无法控制 VPN/TUN 或透明代理。

## 安装

先下载整个仓库 ZIP 并解压。**用管理员身份打开 Windows PowerShell 5.1**，进入解压目录：

```powershell
Set-Location 'D:\Downloads\GitHubDirect-v0.1.0'  # 改成自己的解压目录
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\parse-and-smoke.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\src\github-direct.ps1 -Mode DryRun
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -IntervalMinutes 30
```

安装后创建两个计划任务：`GitHubDirect-Startup`（系统启动时）和 `GitHubDirect-Refresh`（每 30 分钟）。安装会立即运行一次检测。

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

使用管理员 PowerShell，在解压/仓库目录：

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
- 这是兼容 PowerShell 5.1 的初版，**尚未在实际 Windows 电脑上完成端到端验收**；首次安装建议先运行 DryRun 并审阅日志。

## 参考文档

- [GitHub 官方 IP 地址说明](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/about-githubs-ip-addresses)
- [GitHub Meta API](https://api.github.com/meta)
- [Cloudflare DNS over HTTPS](https://developers.cloudflare.com/1.1.1.1/encryption/dns-over-https/make-api-requests/)
- [Microsoft Schtasks](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/schtasks-create)

## 发布 GitHub Release（仓库所有者执行）

当前连接器无法直接创建仓库或 Release；安装并登录 [GitHub CLI](https://cli.github.com/) 后，在本项目根目录执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\publish.ps1
```

会创建公开仓库 `Shardkiht/github-direct`，推送 `main` 和 `v0.1.0`，并发布包含 ZIP 的 GitHub Release；不会把私有凭据上传进仓库。发布前请先审阅代码。
