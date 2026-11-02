#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$testDir = Join-Path $tempRoot ("GitHubDirect-test-' 安装 " + [guid]::NewGuid().ToString('N'))
try {
    $zip = & (Join-Path $root 'package.ps1') -OutputDirectory $testDir
    $expanded = Join-Path $testDir 'expanded'
    Expand-Archive -LiteralPath $zip -DestinationPath $expanded
    $top = @(Get-ChildItem -LiteralPath $expanded)
    if ($top.Count -ne 1 -or $top[0].Name -ne 'GitHubDirect' -or -not $top[0].PSIsContainer) {
        throw 'ZIP must contain exactly one GitHubDirect folder.'
    }
    $package = $top[0].FullName
    $expected = @('src\github-direct.ps1', 'install.ps1', 'uninstall.ps1', 'launch.ps1',
        '安装.cmd', '卸载.cmd', 'README.md', 'CHANGELOG.md', 'LICENSE')
    $actual = @(Get-ChildItem -LiteralPath $package -Recurse -File)
    if ($actual.Count -ne $expected.Count) { throw 'Unexpected files in release package.' }
    foreach ($rel in $expected) {
        $packed = Join-Path $package $rel
        if (-not (Test-Path -LiteralPath $packed)) { throw "Missing packaged file: $rel" }
        if ((Get-FileHash -LiteralPath $packed).Hash -ne (Get-FileHash -LiteralPath (Join-Path $root $rel)).Hash) {
            throw "Packaged file differs from source: $rel"
        }
    }
    foreach ($entry in @(@{ Name = '安装.cmd'; Action = 'Install' }, @{ Name = '卸载.cmd'; Action = 'Uninstall' })) {
        $cmd = Join-Path $package $entry.Name
        $bytes = [IO.File]::ReadAllBytes($cmd)
        if ($bytes[0] -ne 64) { throw 'CMD launcher must start with @, without a BOM.' }
        $text = [IO.File]::ReadAllText($cmd)
        if (-not $text.Contains('"%~dp0launch.ps1" -Action ' + $entry.Action)) { throw 'Broken launcher path or action.' }
        if (-not $text.Contains('exit /b %errorlevel%')) { throw 'Launcher must propagate failure.' }
    }
    # Evaluate the actual quoting/encoding assignments without invoking UAC or the installer.
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $package 'launch.ps1'), [ref]$tokens, [ref]$errors)
    $assignments = $ast.FindAll({ param($node)
        $node -is [Management.Automation.Language.AssignmentStatementAst] -and
        $node.Left.Extent.Text -in @('$quotedPath', '$command', '$encoded')
    }, $true)
    & {
        $testPath = Join-Path $package 'launch.ps1'
        $Action = 'Install'
        foreach ($assignment in $assignments) { Invoke-Expression ($assignment.Extent.Text.Replace('$PSCommandPath', '$testPath')) }
        $decoded = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($encoded))
        $parsed = [scriptblock]::Create($decoded).Ast.EndBlock.Statements[0].PipelineElements[0]
        if ($parsed.CommandElements[0].Value -ne $testPath) { throw 'Elevation corrupts extracted path.' }
        if ($parsed.CommandElements[2].Value -ne 'Install') { throw 'Elevation loses selected action.' }
    }
    Write-Host 'PASS package layout, contents, launchers and UAC path encoding (spaces, Unicode, apostrophe).'
} finally {
    $resolved = [IO.Path]::GetFullPath($testDir)
    if (-not $resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or
        -not ([IO.Path]::GetFileName($resolved)).StartsWith('GitHubDirect-test-')) { throw 'Unsafe test cleanup path.' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
