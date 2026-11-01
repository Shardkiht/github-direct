#requires -Version 5.1
[CmdletBinding()]
param([ValidateRange(15, 1439)][int]$IntervalMinutes = 30)
$ErrorActionPreference = 'Stop'
$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Please run Windows PowerShell as Administrator.'
}
$dir = Join-Path $env:ProgramData 'GitHubDirect'
New-Item -ItemType Directory -Path $dir -Force | Out-Null
# A SYSTEM task must not execute a script that an unprivileged user can modify.
& icacls.exe $dir /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Failed to secure ProgramData GitHubDirect directory.' }
$src = Join-Path $PSScriptRoot 'src\github-direct.ps1'
if (-not (Test-Path -LiteralPath $src)) { throw "Missing $src" }
$dst = Join-Path $dir 'github-direct.ps1'
Copy-Item -LiteralPath $src -Destination $dst -Force
& icacls.exe $dst /inheritance:r /grant:r '*S-1-5-18:F' '*S-1-5-32-544:F' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Failed to secure installed script.' }
$exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$taskCmd = '"' + $exe + '" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $dst + '" -Mode Update'
foreach ($spec in @(
    @{ Name = 'GitHubDirect-Refresh'; Sc = 'MINUTE'; Mo = $IntervalMinutes },
    @{ Name = 'GitHubDirect-Startup'; Sc = 'ONSTART'; Mo = $null }
)) {
    $args = @('/Create', '/F', '/TN', $spec.Name, '/TR', $taskCmd,
        '/SC', $spec.Sc, '/RU', 'SYSTEM', '/RL', 'HIGHEST')
    if ($null -ne $spec.Mo) { $args += @('/MO', [string]$spec.Mo) }
    & schtasks.exe @args
    if ($LASTEXITCODE -ne 0) { throw "Cannot register scheduled task $($spec.Name)" }
}
Write-Host "Scheduled tasks created. Interval: $IntervalMinutes minutes; startup task enabled."
Write-Host 'Running first update (may take a few minutes)...'
& $exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $dst -Mode Update
Write-Host "Done. Logs: $dir\github-direct.log"
