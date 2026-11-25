# Flutter требует Developer Mode для создания symlink плагинов. Если его нет,
# эту же задачу выполняют NTFS junction — они работают без прав администратора.
# Запускать после `flutter pub get`, если он остановился на "symlink support".
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$manifest = Join-Path $projectRoot '.flutter-plugins-dependencies'
if (-not (Test-Path -LiteralPath $manifest)) {
    throw 'Сначала выполните flutter pub get, чтобы появился .flutter-plugins-dependencies'
}

$linksDir = Join-Path $projectRoot 'windows\flutter\ephemeral\.plugin_symlinks'
New-Item -ItemType Directory -Path $linksDir -Force | Out-Null

$dependencies = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
foreach ($plugin in $dependencies.plugins.windows) {
    $name = $plugin.name
    $target = ($plugin.path -replace '\\\\', '\').TrimEnd('\', '/')
    $link = Join-Path $linksDir $name

    if (Test-Path -LiteralPath $link) {
        continue
    }
    & cmd /c mklink /J $link $target | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Не удалось создать junction: $name -> $target"
    }
    Write-Host "Linked: $name"
}

Write-Host 'Готово. Повторите flutter pub get.'
