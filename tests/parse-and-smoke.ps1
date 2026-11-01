#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$files = @('src\github-direct.ps1', 'install.ps1', 'uninstall.ps1', 'publish.ps1')
foreach ($rel in $files) {
    $f = Join-Path $root $rel
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$tokens, [ref]$errors)
    if (@($errors).Count -ne 0) {
        foreach ($e in $errors) { Write-Error "${rel}: $($e.Message) at line $($e.Extent.StartLineNumber)" }
        throw "PowerShell parsing failed: $rel"
    }
    Write-Host "OK parse: $rel"
}
Write-Host 'PASS syntax; live DryRun needs Windows network testing.'
