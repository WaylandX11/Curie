#Requires -Version 5.1
<#
.SYNOPSIS
    Упаковывает portable-сборку Curie Windows в ZIP для GitHub Releases.

.DESCRIPTION
    Берёт готовую папку build\windows\x64\runner\Release, проверяет Xray-ядро
    и иконку трея, затем собирает архив вида
    Curie-26.11.25.1459-alpha-windows-x64.zip с корневой папкой Curie\.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\package-release.ps1
#>
[CmdletBinding()]
param(
    [string]$BuildDir,
    [string]$OutDir
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

if (-not $BuildDir) {
    $BuildDir = Join-Path $root 'build\windows\x64\runner\Release'
}
if (-not $OutDir) {
    $OutDir = Join-Path $root 'dist'
}

$stampPath = Join-Path $root 'lib\src\generated\build_info.dart'
$stampSource = Get-Content -LiteralPath $stampPath -Raw -Encoding UTF8
$stampMatch = [regex]::Match($stampSource, "buildStamp\s*=\s*'([^']+)'")
if (-not $stampMatch.Success) {
    throw "Не найден buildStamp в $stampPath"
}
$version = $stampMatch.Groups[1].Value
$assetName = "Curie-$version-alpha-windows-x64.zip"
$zipPath = Join-Path $OutDir $assetName

foreach ($relative in @(
    'Curie.exe',
    'xray.exe',
    'flutter_windows.dll',
    'data\app.so',
    'data\flutter_assets\assets\tray_icon.png'
)) {
    $candidate = Join-Path $BuildDir $relative
    if (-not (Test-Path -LiteralPath $candidate)) {
        throw "Нет файла сборки: $candidate. Сначала выполните flutter build windows --release"
    }
}

$corePath = Join-Path $root 'lib\src\generated\core_info.dart'
$coreSource = Get-Content -LiteralPath $corePath -Raw -Encoding UTF8
$coreMatch = [regex]::Match($coreSource, "libXrayVersion\s*=\s*'([^']+)'")
$coreVersion = if ($coreMatch.Success) { $coreMatch.Groups[1].Value } else { 'unknown' }

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$stageRoot = Join-Path $OutDir 'stage'
$stage = Join-Path $stageRoot 'Curie'
if (Test-Path -LiteralPath $stageRoot) {
    Remove-Item -LiteralPath $stageRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $stage -Force | Out-Null

Get-ChildItem -LiteralPath $BuildDir -Force | Copy-Item -Destination $stage -Recurse -Force

$notes = @"
Curie Alpha $version

Xray-core: $coreVersion

Установка: распакуйте архив в любую папку и запустите Curie.exe.
Ярлык можно создать scripts\create-shortcut.ps1 из исходников репозитория.
"@
Set-Content -LiteralPath (Join-Path $stage 'RELEASE_NOTES.txt') -Value $notes -Encoding UTF8

Compress-Archive -Path $stage -DestinationPath $zipPath -Force
Remove-Item -LiteralPath $stageRoot -Recurse -Force

$hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host "ZIP: $zipPath"
Write-Host "SHA256: $hash"
