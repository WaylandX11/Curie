#Requires -Version 5.1
<#
.SYNOPSIS
    Ставит версию Windows-сборки в формате YY.MM.DD.HHMM.

.DESCRIPTION
    Логика та же, что у Android: пользователь видит YY.MM.DD.HHMM, а в
    pubspec уходит YY.MM.DD+монотонный счётчик минут с 2020-01-01 — build
    number обязан только расти. Windows-версия живёт отдельно от Android и
    всегда помечается каналом alpha.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\set-version.ps1
#>
[CmdletBinding()]
param(
    [datetime]$Now = (Get-Date)
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

$stamp = $Now.ToString('yy.MM.dd.HHmm')
$versionName = $Now.ToString('yy.MM.dd')
$epoch = [datetime]::SpecifyKind([datetime]'2020-01-01T00:00:00', [System.DateTimeKind]::Utc)
$buildNumber = [int][math]::Floor(($Now.ToUniversalTime() - $epoch).TotalMinutes)

function Write-Utf8NoBom {
    param([string]$Path, [string]$Content)
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
}

# --- pubspec.yaml: версия пакета и монотонный build number -------------------
$pubspecPath = Join-Path $root 'pubspec.yaml'
$pubspec = Get-Content -LiteralPath $pubspecPath -Raw -Encoding UTF8
$pubspec = [regex]::Replace($pubspec, '(?m)^version:.*$', "version: $versionName+$buildNumber")
Write-Utf8NoBom -Path $pubspecPath -Content $pubspec

# --- Dart: строка, которую видит пользователь ------------------------------
$stampPath = Join-Path $root 'lib\src\generated\build_info.dart'
$content = Get-Content -LiteralPath $stampPath -Raw -Encoding UTF8
$content = [regex]::Replace(
    $content,
    "buildStamp\s*=\s*'[^']+'",
    ("buildStamp = '{0}'" -f $stamp)
)
Write-Utf8NoBom -Path $stampPath -Content $content

# --- Windows Resource: версия в свойствах Curie.exe ------------------------
$rcPath = Join-Path $root 'windows\runner\Runner.rc'
$rc = Get-Content -LiteralPath $rcPath -Raw -Encoding UTF8
if ($rc -notmatch '#define CURIE_VERSION_STRING "[^"]+"') {
    throw "Не найден CURIE_VERSION_STRING в $rcPath"
}
$rc = [regex]::Replace(
    $rc,
    '#define CURIE_VERSION_STRING "[^"]+"',
    ('#define CURIE_VERSION_STRING "{0}-alpha"' -f $stamp)
)
Write-Utf8NoBom -Path $rcPath -Content $rc

Write-Host "Windows: $stamp-alpha"
Write-Host "pubspec: $versionName+$buildNumber"
