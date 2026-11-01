#requires -Version 5.1
<#
.SYNOPSIS
  GitHubDirect v0.1.0 - GitHub homepage IPv4 direct-path health checker and hosts manager.
.DESCRIPTION
  No proxy, no DNS/system-wide changes; touches only a clearly marked github.com hosts block.
  Candidates come from HTTPS DNS-over-HTTPS replies and GitHub's official /meta web /32 ranges.
  Requires both official CIDR membership and successful HTTPS certificate validation to select a candidate.
#>
[CmdletBinding()]
param(
    [ValidateSet('Update', 'Status', 'Restore', 'DryRun')]
    [string]$Mode = 'Update',
    [ValidateRange(1, 5)]
    [int]$Probes = 2,
    [ValidateRange(1, 30)]
    [int]$MaxCandidates = 12
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Version = '0.1.0'
$script:BeginMark = '# >>> GitHubDirect managed github.com BEGIN >>>'
$script:EndMark   = '# <<< GitHubDirect managed github.com END <<<'
$script:HostFile = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
$script:DataDir = Join-Path $env:ProgramData 'GitHubDirect'
$script:LogFile = Join-Path $script:DataDir 'github-direct.log'
$script:Curl = Join-Path $env:SystemRoot 'System32\curl.exe'
$script:Direct = $true

function Write-Log([string]$Message) {
    $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $line = "[$stamp] $Message"
    Write-Host $line
    try {
        if (-not (Test-Path -LiteralPath $script:DataDir)) {
            New-Item -ItemType Directory -Force -Path $script:DataDir | Out-Null
        }
        if ((Test-Path -LiteralPath $script:LogFile) -and
            (Get-Item -LiteralPath $script:LogFile).Length -gt 5242880) {
            Move-Item -LiteralPath $script:LogFile -Destination ($script:LogFile + '.old') -Force
        }
        Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8
    } catch { Write-Warning "Cannot write log: $($_.Exception.Message)" }
}

function Test-IPv4([string]$Candidate) {
    [System.Net.IPAddress]$addr = $null
    return ([System.Net.IPAddress]::TryParse($Candidate, [ref]$addr) -and
        $addr.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork -and
        $Candidate -match '^\d{1,3}(\.\d{1,3}){3}$')
}

function Test-InCidr([string]$Address, [string]$Cidr) {
    if (-not (Test-IPv4 $Address)) { return $false }
    $parts = $Cidr.Split('/')
    if ($parts.Count -ne 2 -or -not (Test-IPv4 $parts[0])) { return $false }
    $prefix = 0
    if (-not [int]::TryParse($parts[1], [ref]$prefix) -or $prefix -lt 0 -or $prefix -gt 32) {
        return $false
    }
    $a = ([System.Net.IPAddress]::Parse($Address)).GetAddressBytes()
    $b = ([System.Net.IPAddress]::Parse($parts[0])).GetAddressBytes()
    for ($i = 0; $i -lt 4; $i++) {
        $bits = [Math]::Max(0, [Math]::Min(8, $prefix - 8 * $i))
        if ($bits -eq 0) { continue }
        $mask = (256 - [Math]::Pow(2, (8 - $bits))) -as [int]
        if (($a[$i] -band $mask) -ne ($b[$i] -band $mask)) { return $false }
    }
    return $true
}

function Get-JsonDirect([string]$Url, [string]$Accept = 'application/json') {
    # Uses HTTPS and normal certificate validation; proxy is explicitly disabled.
    $request = [System.Net.HttpWebRequest][System.Net.WebRequest]::Create($Url)
    $request.Proxy = $null
    $request.Timeout = 6500
    $request.ReadWriteTimeout = 6500
    $request.Method = 'GET'
    $request.Accept = $Accept
    $request.UserAgent = 'GitHubDirect/0.1.0 (+local health checks)'
    $response = $null
    $reader = $null
    try {
        $response = $request.GetResponse()
        $reader = [System.IO.StreamReader]::new($response.GetResponseStream(), [Text.Encoding]::UTF8)
        return ($reader.ReadToEnd() | ConvertFrom-Json)
    } finally {
        if ($null -ne $reader) { $reader.Close() }
        if ($null -ne $response) { $response.Close() }
    }
}

function Get-GitHubWebCidrs {
    $meta = Get-JsonDirect 'https://api.github.com/meta'
    if ($null -eq $meta.web -or @($meta.web).Count -eq 0) { throw 'GitHub /meta returned no web CIDRs.' }
    return @($meta.web | Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}/\d{1,2}$' })
}

function Get-DoHCandidates {
    $urls = @(
        'https://dns.alidns.com/resolve?name=github.com&type=A',
        'https://cloudflare-dns.com/dns-query?name=github.com&type=A',
        'https://dns.google/resolve?name=github.com&type=A'
    )
    $collected = New-Object 'System.Collections.Generic.List[string]'
    foreach ($url in $urls) {
        try {
            $data = Get-JsonDirect $url 'application/dns-json'
            if ($data.Status -ne 0) { throw "DoH status $($data.Status)" }
            foreach ($answer in @($data.Answer)) {
                if ($null -ne $answer -and $answer.type -eq 1 -and
                    (Test-IPv4 ([string]$answer.data))) {
                    $collected.Add([string]$answer.data)
                }
            }
        } catch {
            Write-Log "DoH source unavailable ($url): $($_.Exception.Message)"
        }
    }
    return @($collected | Select-Object -Unique)
}

function Read-Hosts {
    $reader = [System.IO.StreamReader]::new($script:HostFile, [Text.Encoding]::Default, $true)
    try {
        $body = $reader.ReadToEnd()
        $encoding = $reader.CurrentEncoding
        return @{ Body = $body; Encoding = $encoding }
    } finally { $reader.Close() }
}

function Get-ManagedIp([string]$Text) {
    $begin = [regex]::Escape($script:BeginMark)
    $end = [regex]::Escape($script:EndMark)
    $match = [regex]::Match($Text, '(?ms)^' + $begin + '\s*\r?\n(.*?)^' + $end + '\s*$')
    if (-not $match.Success) { return $null }
    $line = [regex]::Match($match.Groups[1].Value, '(?m)^\s*(\d{1,3}(?:\.\d{1,3}){3})\s+github\.com\s*$')
    if ($line.Success -and (Test-IPv4 $line.Groups[1].Value)) { return $line.Groups[1].Value }
    return $null
}

function Set-ManagedHosts([AllowNull()][string]$NewIp) {
    $current = Read-Hosts
    $text = $current.Body
    $begin = [regex]::Escape($script:BeginMark)
    $end = [regex]::Escape($script:EndMark)
    $pattern = '(?ms)^' + $begin + '\s*\r?\n.*?^' + $end + '[ \t]*(?:\r?\n)?'
    $blocks = [regex]::Matches($text, $pattern)
    if ($blocks.Count -gt 1) { throw 'More than one managed block found; refusing to overwrite hosts.' }
    if (($text.Contains($script:BeginMark) -or $text.Contains($script:EndMark)) -and $blocks.Count -ne 1) {
        throw 'Malformed managed hosts block; refusing to overwrite hosts.'
    }
    if (-not $NewIp -and $blocks.Count -eq 0) { Write-Log 'No managed hosts block to remove.'; return }
    $stripped = [regex]::Replace($text, $pattern, '')
    # Do not silently override user-defined github.com mappings outside our block.
    foreach ($line in ($stripped -split '\r?\n')) {
        $active = ($line -split '#', 2)[0].Trim()
        if ($active -and $active -match '^\S+\s+(.+)$') {
            $names = $Matches[1] -split '\s+'
            if ($NewIp -and $names -contains 'github.com') {
                throw 'An unmanaged github.com hosts entry already exists; remove it manually before installing.'
            }
        }
    }
    $eol = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $updated = $stripped.TrimEnd("`r", "`n")
    if ($NewIp) {
        if (-not (Test-IPv4 $NewIp)) { throw 'Invalid selected IPv4 address.' }
        $updated += $eol + $eol + $script:BeginMark + $eol +
            "$NewIp github.com" + $eol + $script:EndMark + $eol
    } else {
        $updated += $eol
    }
    if ($updated -eq $text) { Write-Log 'Hosts unchanged.'; return }
    $backup = Join-Path $script:DataDir ("hosts-backup-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + "-$PID")
    [System.IO.File]::Copy($script:HostFile, $backup, $false)
    try {
        [System.IO.File]::WriteAllText($script:HostFile, $updated, $current.Encoding)
        & ipconfig.exe /flushdns | Out-Null
        Write-Log "Hosts updated: github.com => $(if ($NewIp) { $NewIp } else { 'system DNS' }); backup=$backup"
    } catch {
        try { [System.IO.File]::Copy($backup, $script:HostFile, $true) } catch {
            Write-Log "CRITICAL: restoring hosts backup failed: $($_.Exception.Message)"
        }
        throw
    }
}

function Test-Endpoint([string]$Ip) {
    # --resolve preserves the github.com URL, SNI and certificate verification.
    # -q must be first (prevents user curlrc from changing behavior).
    $args = @('-q', '--noproxy', '*', '--ipv4', '--silent', '--show-error',
        '--connect-timeout', '4', '--max-time', '8',
        '--resolve', "github.com:443:$Ip", '--output', 'NUL',
        '--write-out', '%{http_code}|%{time_total}', 'https://github.com/')
    try {
        $value = (& $script:Curl @args 2>$null) -join ''
        if ($LASTEXITCODE -ne 0 -or $value -notmatch '^(\d{3})\|([0-9]+(?:\.[0-9]+)?)$') { return $null }
        $http = [int]$Matches[1]
        if ($http -ne 200 -and $http -ne 301 -and $http -ne 302) { return $null }
        return [double]::Parse($Matches[2], [Globalization.CultureInfo]::InvariantCulture)
    } catch { return $null }
}

if (-not (Test-Path -LiteralPath $script:Curl)) {
    throw "Windows system curl.exe not found: $script:Curl"
}
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$mutex = [System.Threading.Mutex]::new($false, 'Global\GitHubDirect-v01-Hosts')
$locked = $false
try {
    $locked = $mutex.WaitOne(0)
    if (-not $locked) { Write-Host 'Another GitHubDirect instance is running.'; exit 3 }
    if ($Mode -eq 'Status') {
        $hosts = Read-Hosts
        Write-Log "Version $script:Version; current managed IP: $(Get-ManagedIp $hosts.Body)"
        exit 0
    }
    if ($Mode -eq 'Restore') {
        Set-ManagedHosts $null
        Write-Log 'Restored normal github.com DNS resolution.'
        exit 0
    }
    Write-Log "Starting $Mode (version $script:Version)"
    $oldIp = Get-ManagedIp (Read-Hosts).Body
    $cidrs = @(Get-GitHubWebCidrs)
    Write-Log "GitHub official web IPv4 ranges loaded: $($cidrs.Count)"
    $list = New-Object 'System.Collections.Generic.List[string]'
    if ($oldIp) { $list.Add($oldIp) }
    foreach ($ip in @(Get-DoHCandidates)) { $list.Add([string]$ip) }
    # /32 official GitHub web endpoints are safe candidate sources, but still require live HTTPS checks.
    foreach ($cidr in $cidrs) {
        if ($cidr.EndsWith('/32')) { $list.Add($cidr.Split('/')[0]) }
    }
    $allIps = @($list | Where-Object { Test-IPv4 $_ } | Select-Object -Unique)
    $verified = New-Object 'System.Collections.Generic.List[string]'
    foreach ($ip in $allIps) {
        foreach ($cidr in $cidrs) {
            if (Test-InCidr $ip $cidr) { $verified.Add($ip); break }
        }
        if ($verified.Count -ge $MaxCandidates) { break }
    }
    if ($verified.Count -eq 0) { throw 'No IPv4 candidate matched official GitHub web ranges.' }
    $scores = @()
    foreach ($ip in $verified) {
        $success = 0
        $seconds = 0.0
        for ($i = 0; $i -lt $Probes; $i++) {
            $elapsed = Test-Endpoint $ip
            if ($null -ne $elapsed) { $success++; $seconds += [double]$elapsed }
        }
        Write-Log "Candidate $ip : $success/$Probes HTTPS responses"
        if ($success -eq $Probes) {
            $scores += [PSCustomObject]@{ Ip = $ip; Average = ($seconds / $success) }
        }
    }
    if ($scores.Count -eq 0) {
        Write-Log 'No healthy IP; previous mapping kept unchanged (fail-closed).'
        exit 2
    }
    $best = @($scores | Sort-Object Average)[0]
    # Hysteresis: keep incumbent if it remains healthy and within 25% of fastest.
    $incumbent = @($scores | Where-Object { $_.Ip -eq $oldIp })
    if ($incumbent.Count -gt 0 -and $incumbent[0].Average -le $best.Average * 1.25) {
        $best = $incumbent[0]
    }
    Write-Log ("Selected {0} (average {1:N2}s)" -f $best.Ip, $best.Average)
    if ($Mode -eq 'DryRun') { Write-Log 'DryRun: no hosts changes made.'; exit 0 }
    Set-ManagedHosts $best.Ip
} catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    exit 1
} finally {
    if ($locked) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
