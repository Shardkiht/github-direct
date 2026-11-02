#requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Install', 'Uninstall')][string]$Action = 'Install',
    [switch]$Elevated
)
$ErrorActionPreference = 'Stop'
$exitCode = 0
try {
    $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        if ($Elevated) { throw 'Administrator permission was not granted.' }
        # Encode the command so spaces, Unicode and apostrophes in extraction paths survive UAC.
        $quotedPath = $PSCommandPath.Replace("'", "''")
        $command = "& '$quotedPath' -Action $Action -Elevated"
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
        $exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $child = Start-Process -FilePath $exe -Verb RunAs -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded
        ) -Wait -PassThru
        exit $child.ExitCode
    }
    $scriptName = if ($Action -eq 'Install') { 'install.ps1' } else { 'uninstall.ps1' }
    & (Join-Path $PSScriptRoot $scriptName)
} catch {
    Write-Host "Failed: $($_.Exception.Message)" -ForegroundColor Red
    $exitCode = 1
}
[void](Read-Host 'Press Enter to close')
exit $exitCode
