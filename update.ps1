<#
.SYNOPSIS
  Refresh the ONJN blocklist files from the official source.

.DESCRIPTION
  Writes onjn_domains.txt (plain) and onjn_adguard.txt (||domain^). Existing files are only
  replaced when the content changed and the new list passes the sanity checks.
  Works on Windows PowerShell 5.1 and PowerShell 7+.

.PARAMETER SourceFile   Use a local copy of Lista-neagra.txt instead of downloading.
.PARAMETER AllowHttp    Retry over plain http if https fails (injectable in transit).
.PARAMETER MinEntries   Abort if fewer valid domains than this are parsed.
.PARAMETER MaxShrinkPct Abort if the list shrinks by more than this percentage.
.PARAMETER Force        Bypass the safety checks.
.PARAMETER DryRun       Show what would change, write nothing.

.EXAMPLE
  .\update.ps1
  .\update.ps1 -DryRun
  .\update.ps1 -SourceFile .\Lista-neagra.txt -Force
#>
[CmdletBinding()]
param(
    [string]$Url = 'https://onjn.gov.ro/wp-content/uploads/Onjn.gov.ro/Acasa/BlackList/Lista-neagra.txt',
    [string]$OutDir = $PSScriptRoot,
    [string]$SourceFile = '',
    [int]$MinEntries = 500,
    [int]$MaxShrinkPct = 50,
    [switch]$AllowHttp,
    [switch]$Force,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
if (-not $OutDir) { $OutDir = (Get-Location).Path }
$domPath = Join-Path $OutDir 'onjn_domains.txt'
$adgPath = Join-Path $OutDir 'onjn_adguard.txt'
$utf8 = New-Object System.Text.UTF8Encoding $false   # no BOM, LF line endings below

function Get-Source {
    if ($SourceFile) {
        if (-not (Test-Path -LiteralPath $SourceFile)) { throw "SourceFile not found: $SourceFile" }
        return [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $SourceFile).Path)
    }
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
    $headers = @{ 'User-Agent' = 'Mozilla/5.0 (compatible; onjn-list-updater)' }
    function Fetch([string]$u) {
        $r = Invoke-WebRequest -UseBasicParsing -Uri $u -Headers $headers -TimeoutSec 60
        if ($r.Content -is [byte[]]) { return [System.Text.Encoding]::UTF8.GetString($r.Content) }
        return [string]$r.Content
    }
    try { return Fetch $Url }
    catch {
        if ($AllowHttp -and $Url -like 'https://*') {
            Write-Warning 'https download failed, retrying over http'
            return Fetch ('http://' + $Url.Substring(8))
        }
        throw "download failed: $Url ($($_.Exception.Message)). Use -AllowHttp to retry over plain http."
    }
}

$raw = Get-Source
if ([string]::IsNullOrWhiteSpace($raw)) { throw 'source is empty' }

# ---- normalize: strip BOM, lowercase, drop scheme/path/port/leading www ----
$valid = '^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}$'
$set = New-Object 'System.Collections.Generic.HashSet[string]'
$rejected = 0
foreach ($line in ($raw -split "`n")) {
    $s = $line.TrimStart([char]0xFEFF).Trim().ToLowerInvariant()
    if ($s -eq '') { continue }
    $s = $s -replace '^[a-z]+://', ''
    $s = $s -replace '[/?#].*$', ''
    $s = $s -replace ':\d+$', ''
    $s = $s -replace '^www\.', ''
    if ($s -cmatch $valid) { [void]$set.Add($s) } else { $rejected++ }
}
$new = [string[]]@($set)
[Array]::Sort($new, [StringComparer]::Ordinal)
$newN = $new.Count

# ---- sanity checks ----
if (-not $Force -and $newN -lt $MinEntries) {
    throw "only $newN valid domains parsed (MinEntries=$MinEntries); keeping existing files"
}
$oldSet = New-Object 'System.Collections.Generic.HashSet[string]'
if (Test-Path -LiteralPath $domPath) {
    foreach ($l in (Get-Content -LiteralPath $domPath)) { $t = $l.Trim(); if ($t) { [void]$oldSet.Add($t) } }
}
$oldN = $oldSet.Count
if (-not $Force -and $oldN -gt 0) {
    $floor = [math]::Floor($oldN * (100 - $MaxShrinkPct) / 100)
    if ($newN -lt $floor) {
        throw "list shrank from $oldN to $newN (more than $MaxShrinkPct%); rerun with -Force if intended"
    }
}

# ---- diff ----
$added = @($new | Where-Object { -not $oldSet.Contains($_) })
$removed = @($oldSet | Where-Object { -not $set.Contains($_) } | Sort-Object)
if ($added.Count -eq 0 -and $removed.Count -eq 0) {
    Write-Host "no changes ($newN entries)"
    return
}
Write-Host "entries: $oldN -> $newN (+$($added.Count) / -$($removed.Count); $rejected unparseable lines skipped)"
if ($added.Count)   { Write-Host 'added:';   $added   | Select-Object -First 10 | ForEach-Object { "  + $_" }; if ($added.Count -gt 10)   { "  ... and $($added.Count - 10) more" } }
if ($removed.Count) { Write-Host 'removed:'; $removed | Select-Object -First 10 | ForEach-Object { "  - $_" }; if ($removed.Count -gt 10) { "  ... and $($removed.Count - 10) more" } }
if ($DryRun) { Write-Host 'dry run: nothing written'; return }

# ---- write (temp file + move, so a failure never leaves a half-written list) ----
if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }
$header = @(
    '! Title: ONJN Romania unlicensed gambling domains',
    "! Source: $Url",
    "! Updated: $((Get-Date).ToUniversalTime().ToString('yyyy-MM-dd'))",
    "! Entries: $newN",
    '! Note: ||domain^ also blocks all subdomains'
)
$adg = $header + ($new | ForEach-Object { "||$_^" })
[System.IO.File]::WriteAllText("$domPath.tmp", (($new -join "`n") + "`n"), $utf8)
[System.IO.File]::WriteAllText("$adgPath.tmp", (($adg -join "`n") + "`n"), $utf8)
Move-Item -LiteralPath "$domPath.tmp" -Destination $domPath -Force
Move-Item -LiteralPath "$adgPath.tmp" -Destination $adgPath -Force
Write-Host "wrote $domPath and $adgPath"
