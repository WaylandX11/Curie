#Requires -Version 5.1
<#
.SYNOPSIS
    Создаёт ярлык Curie Alpha на рабочем столе и в меню «Пуск».

.DESCRIPTION
    Имя и иконка берутся от собранного Curie.exe — то же название и та же
    launcher-иконка, что у Android-приложения. Скрипт не требует прав
    администратора: ярлыки создаются для текущего пользователя.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\create-shortcut.ps1
#>
[CmdletBinding()]
param(
    [string]$ExePath
)

$ErrorActionPreference = 'Stop'

if (-not $ExePath) {
    $root = Split-Path -Parent $PSScriptRoot
    $ExePath = Join-Path $root 'build\windows\x64\runner\Release\Curie.exe'
}
$exe = (Resolve-Path -LiteralPath $ExePath -ErrorAction Stop).Path
$shell = New-Object -ComObject WScript.Shell
$targets = @(
    [IO.Path]::Combine($shell.SpecialFolders('Desktop'), 'Curie Alpha.lnk'),
    [IO.Path]::Combine($env:APPDATA, 'Microsoft\Windows\Start Menu\Programs', 'Curie Alpha.lnk')
)

foreach ($target in $targets) {
    $shortcut = $shell.CreateShortcut($target)
    $shortcut.TargetPath = $exe
    $shortcut.WorkingDirectory = [IO.Path]::GetDirectoryName($exe)
    $shortcut.IconLocation = "$exe,0"
    $shortcut.Description = 'Curie Alpha — Windows-клиент'
    $shortcut.Save()
    Write-Host "Ярлык: $target"
}
