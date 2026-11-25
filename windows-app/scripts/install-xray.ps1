# Скачивает и проверяет Xray-core, который Curie запускает как обычный процесс.
# Версия совпадает с core.lock.json основного проекта.
$ErrorActionPreference = 'Stop'

$version = 'v26.11.9'
$asset = 'Xray-windows-64.zip'
$expectedHash = '1262522266337b824f07beb8e1375786b437683b3890105469088f8e17e0a69d'
$url = "https://github.com/XTLS/Xray-core/releases/download/$version/$asset"

$projectRoot = Split-Path -Parent $PSScriptRoot
$destination = Join-Path $projectRoot 'tools\xray'
$workDir = Join-Path ([System.IO.Path]::GetTempPath()) "curie-xray-$version-$(Get-Random)"
$archive = Join-Path $workDir $asset

New-Item -ItemType Directory -Path $destination -Force | Out-Null
New-Item -ItemType Directory -Path $workDir -Force | Out-Null

try {
    Write-Host "Downloading $asset ($version)..."
    Invoke-WebRequest -Uri $url -OutFile $archive -UseBasicParsing

    $actualHash = (Get-FileHash -Algorithm SHA256 -Path $archive).Hash.ToLowerInvariant()
    if ($actualHash -ne $expectedHash) {
        throw "SHA256 mismatch: expected $expectedHash, got $actualHash"
    }

    Expand-Archive -Path $archive -DestinationPath $workDir -Force
    $sourceExe = Get-ChildItem -Path $workDir -Filter 'xray.exe' -File -Recurse |
        Select-Object -First 1
    if ($null -eq $sourceExe) {
        throw 'xray.exe not found inside the release archive'
    }

    $targetExe = Join-Path $destination 'xray.exe'
    Copy-Item -Path $sourceExe.FullName -Destination $targetExe -Force
    Write-Host "Installed: $targetExe"
}
finally {
    if (Test-Path -LiteralPath $workDir) {
        Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
