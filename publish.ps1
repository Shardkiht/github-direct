#requires -Version 5.1
<# Creates v0.1.0 release in an EXISTING GitHub repository after reviewing main. #>
[CmdletBinding()]
param([string]$Repository = 'Shardkiht/github-direct')
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw 'Install GitHub CLI (gh) and run gh auth login first.'
}
& gh auth status
if ($LASTEXITCODE -ne 0) { throw 'GitHub CLI is not authenticated. Run gh auth login.' }
$meta = & gh repo view $Repository --json nameWithOwner,visibility,defaultBranchRef 2>&1
if ($LASTEXITCODE -ne 0) { throw "Cannot access $Repository : $meta" }
$info = ($meta | Out-String) | ConvertFrom-Json
if ($info.nameWithOwner -ne $Repository) { throw "Unexpected repository: $($info.nameWithOwner)" }
if ($info.defaultBranchRef.name -ne 'main') { throw 'Expected main as the default branch. Review before publishing.' }
& gh release view v0.1.0 --repo $Repository *> $null
if ($LASTEXITCODE -eq 0) { throw 'v0.1.0 release already exists; refusing to overwrite.' }
$zip = & (Join-Path $PSScriptRoot 'package.ps1')
& gh release create v0.1.0 $zip --repo $Repository --target (git rev-parse HEAD) --title 'v0.1.0' --notes-file RELEASE_NOTES.md
if ($LASTEXITCODE -ne 0) { throw 'GitHub release creation failed.' }
Write-Host "Published: https://github.com/$Repository/releases/tag/v0.1.0"
