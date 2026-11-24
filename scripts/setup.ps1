#Requires -Version 5.1
<#
.SYNOPSIS
    Готовит окружение Curie и создаёт Flutter-проект.

.DESCRIPTION
    1. Клонирует Flutter stable в %USERPROFILE%\dev\flutter (если ещё нет)
    2. Находит Android SDK (ставится вместе с Android Studio)
    3. Ставит Android SDK Command-line Tools, если их нет (Android Studio их не всегда тянет,
       а без них не работают ни лицензии, ни flutter doctor)
    4. Принимает лицензии SDK
    5. Ставит NDK нужной версии (Flutter требует её и сам ставит неправильно)
    6. Создаёт app/ через flutter create с нужными org и именем
    7. Подключает flutter_launcher_icons и кладёт иконки из branding/

    Go и Android NDK не нужны: ядро приходит готовой библиотекой libXray.aar.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\setup.ps1
#>
[CmdletBinding()]
param(
    [string]$FlutterDir
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
if (-not $FlutterDir) { $FlutterDir = Join-Path $env:USERPROFILE 'dev\flutter' }

$brand = Get-Content (Join-Path $root 'branding\brand.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$appDir = Join-Path $root 'app'

Write-Host "== Curie: подготовка окружения ==" -ForegroundColor Cyan
Write-Host "Проект:        $root"
Write-Host "Flutter:       $FlutterDir"
Write-Host "applicationId: $($brand.applicationId)"

# --- 1. Flutter -------------------------------------------------------------
$flutter = Join-Path $FlutterDir 'bin\flutter.bat'
if (-not (Test-Path $flutter)) {
    Write-Host "`n[1/7] Клонирую Flutter stable (первый раз это несколько минут)..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Force -Path (Split-Path $FlutterDir) | Out-Null
    git clone --depth 1 -b stable https://github.com/flutter/flutter.git $FlutterDir
    if ($LASTEXITCODE -ne 0) { throw "git clone Flutter не удался" }
} else {
    Write-Host "`n[1/7] Flutter уже на месте."
}
& $flutter --version
& $flutter config --no-analytics | Out-Null

# --- 2. Android SDK ---------------------------------------------------------
Write-Host "`n[2/7] Ищу Android SDK..." -ForegroundColor Yellow
$sdkCandidates = @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, (Join-Path $env:LOCALAPPDATA 'Android\Sdk'))
$sdk = $sdkCandidates | Where-Object { $_ -and (Test-Path (Join-Path $_ 'platform-tools')) } | Select-Object -First 1

if (-not $sdk) {
    Write-Host ""
    Write-Host "Android SDK не найден." -ForegroundColor Red
    Write-Host "Поставьте Android Studio (она приносит JDK и SDK), запустите её один раз и повторите:"
    Write-Host "  https://developer.android.com/studio"
    Write-Host "После установки SDK обычно лежит в $env:LOCALAPPDATA\Android\Sdk"
    exit 2
}
Write-Host "SDK: $sdk"
& $flutter config --android-sdk $sdk | Out-Null

# --- 3. Command-line tools --------------------------------------------------
Write-Host "`n[3/7] Проверяю Android SDK Command-line Tools..." -ForegroundColor Yellow
$sdkManager = Join-Path $sdk 'cmdline-tools\latest\bin\sdkmanager.bat'
if (-not (Test-Path $sdkManager)) {
    # Android Studio ставит платформы и build-tools, но не cmdline-tools: без них
    # не работают ни sdkmanager, ни flutter doctor --android-licenses.
    $fallbackUrl = 'https://dl.google.com/android/repository/commandlinetools-win-16111833_latest.zip'
    $zipUrl = $fallbackUrl
    try {
        $repo = Invoke-WebRequest -Uri 'https://dl.google.com/android/repository/repository2-3.xml' -UseBasicParsing
        $best = [regex]::Matches($repo.Content, 'commandlinetools-win-(\d+)_latest\.zip') |
            ForEach-Object { [int64]$_.Groups[1].Value } |
            Sort-Object -Unique |
            Select-Object -Last 1
        if ($best) { $zipUrl = "https://dl.google.com/android/repository/commandlinetools-win-$best`_latest.zip" }
    } catch {
        Write-Host "  Не смог узнать последнюю версию, беру проверенную: $fallbackUrl"
    }

    Write-Host "  Скачиваю $zipUrl"
    $zip = Join-Path $env:TEMP 'curie-cmdline-tools.zip'
    $tmp = Join-Path $env:TEMP ('curie-cmdline-tools-' + [guid]::NewGuid().ToString('N'))
    try {
        Invoke-WebRequest -Uri $zipUrl -OutFile $zip -UseBasicParsing
        Expand-Archive -Path $zip -DestinationPath $tmp -Force
        $dest = Join-Path $sdk 'cmdline-tools\latest'
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        Copy-Item (Join-Path $tmp 'cmdline-tools\*') $dest -Recurse -Force
    } finally {
        Remove-Item $zip -Force -ErrorAction SilentlyContinue
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (-not (Test-Path $sdkManager)) { throw "cmdline-tools установились, но $sdkManager не найден" }
    Write-Host "  Установлены: $sdkManager"
} else {
    Write-Host "  Уже на месте."
}

# --- 4. Лицензии ------------------------------------------------------------
Write-Host "`n[4/7] Принимаю лицензии Android SDK..." -ForegroundColor Yellow
$previous = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    $yes = ("y`r`n" * 100)
    $yes | & $sdkManager --sdk_root="$sdk" --licenses *> $null
} catch {
    Write-Host "  Лицензии не принялись автоматически: $_" -ForegroundColor Yellow
    Write-Host "  Можно позже принять вручную: Android Studio -> SDK Manager -> SDK Tools"
} finally {
    $ErrorActionPreference = $previous
}

# --- 5. NDK -----------------------------------------------------------------
Write-Host "`n[5/7] Проверяю Android NDK..." -ForegroundColor Yellow
# Flutter требует конкретную версию NDK и пытается поставить её сам, но передаёт
# пакет в старом виде "ndk;<версия>", который новый Android CLI не понимает.
# Ставим заранее — тогда сборка просто находит готовый NDK.
$ndkVersion = '28.2.13676358'
$extensionFile = Join-Path $FlutterDir 'packages\flutter_tools\gradle\src\main\kotlin\FlutterExtension.kt'
if (Test-Path $extensionFile) {
    $m = [regex]::Match((Get-Content $extensionFile -Raw), 'val ndkVersion: String = "([^"]+)"')
    if ($m.Success) { $ndkVersion = $m.Groups[1].Value }
}
$ndkMarker = Join-Path $sdk "ndk\$ndkVersion\source.properties"
if (-not (Test-Path $ndkMarker)) {
    Write-Host "  Ставлю NDK $ndkVersion (несколько ГБ, это надолго)..."
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        ("y`r`n" * 20) | & $sdkManager --sdk_root="$sdk" --install "ndk/$ndkVersion" *> $null
    } finally {
        $ErrorActionPreference = $previous
    }
    if (-not (Test-Path $ndkMarker)) {
        Write-Host "  NDK не установился. Поставьте вручную: Android Studio -> SDK Manager -> SDK Tools -> NDK (Side by side) $ndkVersion" -ForegroundColor Yellow
    }
} else {
    Write-Host "  NDK $ndkVersion уже на месте."
}

# --- 6. Проект --------------------------------------------------------------
if (-not (Test-Path (Join-Path $appDir 'pubspec.yaml'))) {
    Write-Host "`n[6/7] Создаю Flutter-проект в app/..." -ForegroundColor Yellow
    & $flutter create --org $brand.org --project-name $brand.projectName `
        --platforms=android,ios --empty $appDir
    if ($LASTEXITCODE -ne 0) { throw "flutter create не удался" }
} else {
    Write-Host "`n[6/7] app/ уже существует, не трогаю."
}

# --- 7. Иконки --------------------------------------------------------------
Write-Host "`n[7/7] Подключаю иконки и зависимости..." -ForegroundColor Yellow
$assets = Join-Path $appDir 'assets'
New-Item -ItemType Directory -Force -Path $assets | Out-Null
Copy-Item (Join-Path $root 'branding\icon.png') (Join-Path $assets 'icon.png') -Force
Copy-Item (Join-Path $root 'branding\icon_foreground.png') (Join-Path $assets 'icon_foreground.png') -Force

Push-Location $appDir
try {
    & $flutter pub add dev:flutter_launcher_icons
    if ($LASTEXITCODE -ne 0) { throw "flutter pub add flutter_launcher_icons не удался" }

    $pubspecPath = Join-Path $appDir 'pubspec.yaml'
    $pubspec = Get-Content $pubspecPath -Raw -Encoding UTF8
    if ($pubspec -notmatch '(?m)^flutter_launcher_icons:') {
        $pubspec += @"

# Значки генерируются из branding/icon*.png командой:
#   dart run flutter_launcher_icons
flutter_launcher_icons:
  android: true
  ios: true
  remove_alpha_ios: true
  image_path: "assets/icon.png"
  adaptive_icon_background: "$($brand.darkBackground)"
  adaptive_icon_foreground: "assets/icon_foreground.png"
  min_sdk_android: 24
"@
        [System.IO.File]::WriteAllText($pubspecPath, $pubspec, (New-Object System.Text.UTF8Encoding($false)))
    }
    & $flutter pub get | Out-Null
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "Готово." -ForegroundColor Green
Write-Host "Дальше:"
Write-Host "  1) powershell -ExecutionPolicy Bypass -File scripts\sync-core.ps1   # вшить ядро"
Write-Host "  2) cd app; flutter run                                             # запустить на телефоне"
