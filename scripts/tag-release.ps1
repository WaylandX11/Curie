#Requires -Version 5.1
<#
.SYNOPSIS
    Создаёт аннотированный git-тег для текущей версии Curie.

.DESCRIPTION
    Версию берёт из app/lib/src/generated/build_info.dart (YY.MM.DD.HHMM),
    поэтому тэг всегда совпадает с тем, что показывает приложение.
    Без -Publish только показывает, какой тэг был бы создан: так локальные
    подверсии случайно не уходят на GitHub.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\tag-release.ps1
    powershell -ExecutionPolicy Bypass -File scripts\tag-release.ps1 -Publish
    powershell -ExecutionPolicy Bypass -File scripts\tag-release.ps1 -Publish -Push
#>
[CmdletBinding()]
param(
    [string]$Suffix = 'alpha',
    [switch]$Publish,
    [switch]$Push
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$stampPath = Join-Path $root 'app\lib\src\generated\build_info.dart'
$content = Get-Content $stampPath -Raw -Encoding UTF8
$match = [regex]::Match($content, "buildStamp\s*=\s*'([^']+)'")
if (-not $match.Success) {
    throw "Не найден buildStamp в $stampPath — сначала запустите scripts\set-version.ps1"
}

$stamp = $match.Groups[1].Value
$tag = "v$stamp"
if ($Suffix) { $tag += "-$Suffix" }

$existing = & git -C $root tag --list $tag
if ($existing) { throw "Тэг $tag уже существует" }

if (-not $Publish) {
    Write-Host "Пробный запуск: тэг $tag НЕ создан. Добавьте -Publish, когда решите опубликовать." -ForegroundColor Yellow
    return
}

& git -C $root tag -a $tag -m "Curie $tag"
if ($LASTEXITCODE -ne 0) { throw "git tag завершился с кодом $LASTEXITCODE" }

Write-Host "Создан тэг: $tag" -ForegroundColor Green
if ($Push) {
    & git -C $root push --follow-tags
    if ($LASTEXITCODE -ne 0) { throw "git push завершился с кодом $LASTEXITCODE" }
} else {
    Write-Host "Когда добавите remote: git push --follow-tags"
}
