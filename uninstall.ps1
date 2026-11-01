#requires -Version 5.1
[CmdletBinding()]
param([switch]$RemoveLogs)
$ErrorActionPreference = 'Stop'
$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Please run Windows PowerShell as Administrator.'
}
foreach ($name in @('GitHubDirect-Refresh', 'GitHubDirect-Startup')) {
    try { & schtasks.exe /End /TN $name 2>$null | Out-Null } catch {}
    try { & schtasks.exe /Delete /TN $name /F 2>$null | Out-Null } catch { Write-Warning "Could not delete $name : $_" }
}
$dst = Join-Path $env:ProgramData 'GitHubDirect\github-direct.ps1'
if (Test-Path -LiteralPath $dst) {
    & (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') `
        -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $dst -Mode Restore
    if ($LASTEXITCODE -ne 0) { throw 'Hosts restoration failed; review hosts before deleting scripts.' }
}
Remove-Item -LiteralPath $dst -ErrorAction SilentlyContinue
if ($RemoveLogs) {
    Remove-Item -LiteralPath (Join-Path $env:ProgramData 'GitHubDirect') -Recurse -Force
}
Write-Host 'Uninstalled. Hosts restored. Backups/logs retained unless -RemoveLogs was used.'
