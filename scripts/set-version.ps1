#Requires -Version 5.1
<#
.SYNOPSIS
    Ставит версию сборки в формате YY.MM.DD.HHMM.

.DESCRIPTION
    В интерфейсе и в сторах версия выглядит как 26.11.23.1815.
    pubspec получает version: YY.MM.DD+<минуты с 2020-01-01> — код сборки
    обязан только расти, а HHMM между сутками уменьшается, поэтому для
    versionCode берём монотонный счётчик минут.

    Отображаемая строка кладётся в app/lib/src/generated/build_info.dart.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\set-version.ps1
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

# --- pubspec ----------------------------------------------------------------
$pubspecPath = Join-Path $root 'app\pubspec.yaml'
$pubspec = Get-Content $pubspecPath -Raw -Encoding UTF8
$pubspec = [regex]::Replace($pubspec, '(?m)^version:.*$', "version: $versionName+$buildNumber")
[System.IO.File]::WriteAllText($pubspecPath, $pubspec, (New-Object System.Text.UTF8Encoding($false)))

# --- константа для интерфейса ------------------------------------------------
$generatedDir = Join-Path $root 'app\lib\src\generated'
New-Item -ItemType Directory -Force -Path $generatedDir | Out-Null
$dart = @"
// Сгенерировано scripts/set-version.ps1. Не редактировать вручную.

/// Версия сборки в формате YY.MM.DD.HHMM.
const String buildStamp = '$stamp';
"@
[System.IO.File]::WriteAllText(
    (Join-Path $generatedDir 'build_info.dart'),
    $dart,
    (New-Object System.Text.UTF8Encoding($false))
)

Write-Host "Версия: $stamp" -ForegroundColor Green
Write-Host "pubspec: $versionName+$buildNumber"
