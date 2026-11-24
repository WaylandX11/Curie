#Requires -Version 5.1
<#
.SYNOPSIS
    Скачивает последний релиз libXray и кладёт ядро в проект.

.DESCRIPTION
    Android: libXray.aar -> app/android/app/libs/libXray.aar
    Apple:   LibXray.xcframework -> app/ios/Frameworks/ (флаг -Apple)
    SHA-256 сверяется с digest из GitHub API, версия пишется в core.lock.json.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\sync-core.ps1
    powershell -ExecutionPolicy Bypass -File scripts\sync-core.ps1 -Apple
#>
[CmdletBinding()]
param(
    [string]$Repo = 'XTLS/libXray',
    [switch]$Apple
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$assetName = if ($Apple) { 'libxray-apple-cgo.zip' } else { 'libxray-android.zip' }

Write-Host "== Curie: обновление ядра ==" -ForegroundColor Cyan
Write-Host "Релиз: $Repo / $assetName"

$headers = @{ 'User-Agent' = 'curie-sync'; 'Accept' = 'application/vnd.github+json' }
$release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers $headers
$asset = $release.assets | Where-Object { $_.name -eq $assetName } | Select-Object -First 1
if (-not $asset) { throw "В релизе $($release.tag_name) нет $assetName" }

$tmp = Join-Path $env:TEMP ("curie-core-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

try {
    $zip = Join-Path $tmp $assetName
    Write-Host "Скачиваю $([math]::Round($asset.size / 1MB, 1)) МБ..."
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -UseBasicParsing

    $actual = (Get-FileHash -Path $zip -Algorithm SHA256).Hash.ToLower()
    if ($asset.digest) {
        $expected = ($asset.digest -replace '^sha256:', '').ToLower()
        if ($actual -ne $expected) { throw "sha256 не совпал: ожидали $expected, получили $actual" }
        Write-Host "sha256 OK: $actual"
    } else {
        Write-Host "sha256 (digest в API отсутствует): $actual" -ForegroundColor Yellow
    }

    Expand-Archive -Path $zip -DestinationPath $tmp -Force

    if ($Apple) {
        $src = Get-ChildItem -Path $tmp -Recurse -Directory -Filter 'LibXray.xcframework' | Select-Object -First 1
        if (-not $src) { throw "В архиве нет LibXray.xcframework" }
        $dest = Join-Path $root 'app\ios\Frameworks'
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        $target = Join-Path $dest 'LibXray.xcframework'
        if (Test-Path $target) { Remove-Item $target -Recurse -Force }
        Copy-Item $src.FullName $target -Recurse
        $installed = $target
    } else {
        $src = Get-ChildItem -Path $tmp -Recurse -File -Filter 'libXray.aar' | Select-Object -First 1
        if (-not $src) { throw "В архиве нет libXray.aar" }
        $dest = Join-Path $root 'app\android\app\libs'
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        $installed = Join-Path $dest 'libXray.aar'
        Copy-Item $src.FullName $installed -Force
    }
} finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

$lock = [ordered]@{
    library     = 'libXray'
    version     = $release.tag_name
    publishedAt = $release.published_at
    asset       = $assetName
    sha256      = $actual
    target      = $installed.Substring($root.Length).TrimStart('\')
    installedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
}
$lockPath = Join-Path $root 'core.lock.json'
# Без BOM: CI читает файл через Python json, а BOM ломает разбор.
[System.IO.File]::WriteAllText(
    $lockPath,
    ($lock | ConvertTo-Json),
    (New-Object System.Text.UTF8Encoding($false))
)

# Версия ядра нужна и в интерфейсе: генерируем константу, чтобы «О приложении»
# показывало то, что реально вшито в сборку, а не то, что вспомнил разработчик.
if (-not $Apple) {
    $generatedDir = Join-Path $root 'app\lib\src\generated'
    New-Item -ItemType Directory -Force -Path $generatedDir | Out-Null
    $dart = @"
// Сгенерировано scripts/sync-core.ps1. Не редактировать вручную.

/// Версия обёртки libXray, вшитой в сборку.
const String libXrayVersion = '$($release.tag_name)';

/// SHA-256 архива релиза — то, что было проверено при загрузке.
const String libXraySha256 = '$actual';
"@
    [System.IO.File]::WriteAllText(
        (Join-Path $generatedDir 'core_info.dart'),
        $dart,
        (New-Object System.Text.UTF8Encoding($false))
    )
}

Write-Host ""
Write-Host "Ядро $($release.tag_name) установлено:" -ForegroundColor Green
Write-Host "  $installed"
Write-Host "  версия записана в core.lock.json"
Write-Host ""
Write-Host "Не забудьте поднять versionCode/versionName в app/pubspec.yaml перед релизом."
