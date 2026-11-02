#requires -Version 5.1
[CmdletBinding()]
param([string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $PSScriptRoot 'dist' }
$files = @('src', 'README.md', 'CHANGELOG.md', 'LICENSE', 'install.ps1',
    'uninstall.ps1', 'launch.ps1', '安装.cmd', '卸载.cmd')
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$stage = Join-Path ([IO.Path]::GetTempPath()) ('GitHubDirect-package-' + [guid]::NewGuid().ToString('N'))
$folder = Join-Path $stage 'GitHubDirect'
try {
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    foreach ($file in $files) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination $folder -Recurse
    }
    $zip = Join-Path $OutputDirectory 'GitHubDirect-v0.1.0.zip'
    Compress-Archive -LiteralPath $folder -DestinationPath $zip -CompressionLevel Optimal -Force
    Write-Output $zip
} finally {
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $stage = [IO.Path]::GetFullPath($stage)
    if (-not $stage.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or
        -not ([IO.Path]::GetFileName($stage)).StartsWith('GitHubDirect-package-')) { throw 'Unsafe staging cleanup path.' }
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
}
