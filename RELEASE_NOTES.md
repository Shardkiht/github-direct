# GitHubDirect v0.1.0

Windows PowerShell 5.1 实验性 GitHub 直连优化工具。无第三方代理，只优化 `github.com` 主站。

- 支持 Windows 开机与每 30 分钟定时刷新。
- 加密 DoH 解析候选 IP，并与 GitHub 官方 Meta API Web CIDR 核验。
- 使用直接 HTTPS 验证目标 IP 的证书、响应状态和速度。
- 保留 Hosts 原有设置，仅管理明确标记的 `github.com` 区块；支持备份、日志、恢复与卸载。
- 受网络策略和 GitHub IP 变化影响，无法保证所有网络均可稳定直连，初次安装前请测试 `DryRun`。

需要 Windows 10/11、Windows PowerShell 5.1、Windows 自带 curl.exe，安装需要管理员权限。
