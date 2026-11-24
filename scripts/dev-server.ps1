#Requires -Version 5.1
<#
.SYNOPSIS
    Локальный Xray-сервер для проверки туннеля без провайдера.

.DESCRIPTION
    Скачивает официальный Xray-core для Windows в tools/dev-server/, поднимает
    Shadowsocks-inbound на 127.0.0.1 и печатает ссылку, которую можно вставить
    в Curie, запущенный в эмуляторе (эмулятор видит хост как 10.0.2.2).

    Это только для разработки: никакого TLS, пароль известен, слушает localhost.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\dev-server.ps1
    powershell -ExecutionPolicy Bypass -File scripts\dev-server.ps1 -NoRun
#>
[CmdletBinding()]
param(
    [int]$Port = 10086,
    [string]$ClientHost = '10.0.2.2',
    [string]$Password = 'curie-dev-password',
    [string]$Method = 'aes-256-gcm',
    [switch]$NoRun
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$dir = Join-Path $root 'tools\dev-server'
$exe = Join-Path $dir 'xray.exe'
New-Item -ItemType Directory -Force -Path $dir | Out-Null

if (-not (Test-Path $exe)) {
    Write-Host "== Скачиваю Xray-core для Windows ==" -ForegroundColor Cyan
    $headers = @{ 'User-Agent' = 'curie-dev-server' }
    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/XTLS/Xray-core/releases/latest' -Headers $headers
    $asset = $release.assets | Where-Object { $_.name -eq 'Xray-windows-64.zip' } | Select-Object -First 1
    if (-not $asset) { throw "В релизе $($release.tag_name) нет Xray-windows-64.zip" }

    $zip = Join-Path $dir 'xray.zip'
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -UseBasicParsing
    if ($asset.digest) {
        $expected = ($asset.digest -replace '^sha256:', '').ToLower()
        $actual = (Get-FileHash -Path $zip -Algorithm SHA256).Hash.ToLower()
        if ($actual -ne $expected) { throw "sha256 не совпал: $actual != $expected" }
    }
    Expand-Archive -Path $zip -DestinationPath $dir -Force
    Remove-Item $zip -Force
    Write-Host "  $($release.tag_name) -> $exe"
}

$config = [ordered]@{
    log       = @{ loglevel = 'warning' }
    inbounds  = @(
        [ordered]@{
            listen   = '127.0.0.1'
            port     = $Port
            protocol = 'shadowsocks'
            settings = [ordered]@{
                method   = $Method
                password = $Password
                network  = 'tcp,udp'
            }
        }
    )
    outbounds = @(@{ protocol = 'freedom' })
}
$configPath = Join-Path $dir 'config.json'
$config | ConvertTo-Json -Depth 8 | Set-Content -Path $configPath -Encoding UTF8

$userInfo = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("${Method}:${Password}"))
$userInfo = $userInfo.TrimEnd('=').Replace('+', '-').Replace('/', '_')
$link = "ss://$userInfo@${ClientHost}:$Port#CurieDev"

Write-Host ""
Write-Host "Ссылка для Curie в эмуляторе:" -ForegroundColor Green
Write-Host "  $link"
Write-Host ""
Write-Host "Сервер слушает 127.0.0.1:$Port (эмулятор доходит до него через $ClientHost)."
Write-Host "Остановить: Ctrl+C."
Write-Host ""

if (-not $NoRun) {
    & $exe run -c $configPath
}
