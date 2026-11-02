# GitHubDirect v0.1.0

Windows PowerShell 5.1 实验性 GitHub 直连优化工具。无第三方代理，只优化 `github.com` 主站。

- 支持 Windows 开机与每 30 分钟定时刷新。
- 加密 DoH 解析候选 IP，并与 GitHub 官方 Meta API Web CIDR 核验。
- 使用直接 HTTPS 验证目标 IP 的证书、响应状态和速度。
- 保留 Hosts 原有设置，仅管理明确标记的 `github.com` 区块；支持备份、日志、恢复与卸载。
- 受网络策略和 GitHub IP 变化影响，无法保证所有网络均可稳定直连，可在安装前使用 `DryRun` 检查，安装后请审阅日志。

需要 Windows 10/11、Windows PowerShell 5.1、Windows 自带 curl.exe，安装需要管理员权限。

## 安装

下载 **GitHubDirect-v0.1.0.zip** → 解压 → 打开 **GitHubDirect** 文件夹 → 双击 **安装.cmd** → 同意管理员权限。安装后会立即检测，并设置开机及每 30 分钟自动刷新。窗口会保留检测结果，按 Enter 关闭。卸载时双击 **卸载.cmd**。

不需要手动输入命令或安装额外运行环境。请完整解压后运行，不要选择 Source code 压缩包。

验证范围：Windows PowerShell 5.1 离线语法与安装包检查；未执行真实提权安装、Hosts 修改、任务调度或网络端到端验收。
