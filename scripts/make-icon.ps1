#Requires -Version 5.1
<#
.SYNOPSIS
    Рисует иконки Curie без внешних зависимостей (GDI+).

.DESCRIPTION
    branding/icon.png            — непрозрачная 1024x1024, для iOS и листингов сторов
    branding/icon_foreground.png — прозрачная 1024x1024, для Android adaptive icon
                                   (знак занимает ~61% холста, чтобы влезть в safe zone)

    Дополнительно пересобирает mipmap-* и drawable-* в Android-проекте.
    Иконка — монограмма «C» дугой с двумя электронными орбитами: Кюри, рентген, радий.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\make-icon.ps1
#>
[CmdletBinding()]
param(
    [string]$OutDir,
    [string]$AndroidResDir
)

$ErrorActionPreference = 'Stop'
if (-not $OutDir) {
    $OutDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'branding'
}

Add-Type -AssemblyName System.Drawing

$S = 1024
$Teal = [System.Drawing.Color]::FromArgb(255, 47, 227, 208)
$Mint = [System.Drawing.Color]::FromArgb(255, 155, 255, 106)

function New-Canvas {
    param([bool]$Transparent)

    $bmp = New-Object System.Drawing.Bitmap($S, $S)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

    if ($Transparent) {
        $g.Clear([System.Drawing.Color]::Transparent)
    } else {
        $rect = New-Object System.Drawing.Rectangle(0, 0, $S, $S)
        $dark = [System.Drawing.Color]::FromArgb(255, 8, 14, 26)
        $navy = [System.Drawing.Color]::FromArgb(255, 18, 34, 58)
        $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $dark, $navy, 55.0)
        $g.FillRectangle($brush, $rect)
        $brush.Dispose()
    }
    return $g
}

function New-RoundPen {
    param([System.Drawing.Color]$Color, [double]$Width)
    $pen = New-Object System.Drawing.Pen($Color, ([single]$Width))
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    return $pen
}

function Draw-Mark {
    param($G, [double]$Scale)

    $cx = $S / 2.0
    $cy = $S / 2.0
    $r = 250.0 * $Scale      # радиус дуги
    $w = 76.0 * $Scale       # толщина дуги

    # --- свечение: несколько широких полупрозрачных штрихов под основным ---
    foreach ($step in @(
            @{ k = 3.1; a = 18 },
            @{ k = 2.2; a = 28 },
            @{ k = 1.55; a = 44 }
        )) {
        $col = [System.Drawing.Color]::FromArgb([int]$step.a, $Teal.R, $Teal.G, $Teal.B)
        $pen = New-RoundPen -Color $col -Width ($w * $step.k)
        $rect = New-Object System.Drawing.RectangleF(([single]($cx - $r)), ([single]($cy - $r)), ([single](2 * $r)), ([single](2 * $r)))
        # дуга с разрывом справа: от 42° на 300°
        $G.DrawArc($pen, $rect, 42.0, 300.0)
        $pen.Dispose()
    }

    # --- основная дуга C ---
    $pen = New-RoundPen -Color $Teal -Width $w
    $rect = New-Object System.Drawing.RectangleF(([single]($cx - $r)), ([single]($cy - $r)), ([single](2 * $r)), ([single](2 * $r)))
    $G.DrawArc($pen, $rect, 42.0, 300.0)
    $pen.Dispose()

    # --- две орбиты, наклонённые в разные стороны ---
    foreach ($angle in @(-26.0, 26.0)) {
        $state = $G.Save()
        $G.TranslateTransform([single]$cx, [single]$cy)
        $G.RotateTransform([single]$angle)

        $orbit = [System.Drawing.Color]::FromArgb(120, $Teal.R, $Teal.G, $Teal.B)
        $pen = New-RoundPen -Color $orbit -Width (7.0 * $Scale)
        $ox = -350.0 * $Scale
        $oy = -134.0 * $Scale
        $G.DrawEllipse($pen, ([single]$ox), ([single]$oy), ([single](700 * $Scale)), ([single](268 * $Scale)))
        $pen.Dispose()

        $G.Restore($state)
    }

    # --- узел-электрон на правом краю верхней орбиты ---
    $nx = $cx + (330.0 * $Scale * [Math]::Cos([Math]::PI * -26 / 180))
    $ny = $cy + (330.0 * $Scale * [Math]::Sin([Math]::PI * -26 / 180))
    $nr = 15.0 * $Scale

    foreach ($step in @(@{ k = 2.8; a = 45 }, @{ k = 1.7; a = 80 })) {
        $col = [System.Drawing.Color]::FromArgb([int]$step.a, $Mint.R, $Mint.G, $Mint.B)
        $brush = New-Object System.Drawing.SolidBrush($col)
        $G.FillEllipse($brush, ([single]($nx - $nr * $step.k)), ([single]($ny - $nr * $step.k)), ([single](2 * $nr * $step.k)), ([single](2 * $nr * $step.k)))
        $brush.Dispose()
    }
    $brush = New-Object System.Drawing.SolidBrush($Mint)
    $G.FillEllipse($brush, ([single]($nx - $nr)), ([single]($ny - $nr)), ([single](2 * $nr)), ([single](2 * $nr)))
    $brush.Dispose()
}

function Save-Resized {
    param(
        [string]$Source,
        [string]$Destination,
        [int]$Size
    )

    $dir = Split-Path -Parent $Destination
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }

    $srcImage = [System.Drawing.Image]::FromFile($Source)
    $bmp = New-Object System.Drawing.Bitmap($Size, $Size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.DrawImage($srcImage, 0, 0, $Size, $Size)
    $g.Dispose()
    $bmp.Save($Destination, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    $srcImage.Dispose()
}

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }
if (-not $AndroidResDir) {
    $AndroidResDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'app\android\app\src\main\res'
}

# 1. Полная иконка: фон + знак. Масштаб увеличен с 1.0 до 1.25 —
#    теперь монограмма занимает ~70% холста вместо ~56%.
$full = Join-Path $OutDir 'icon.png'
$bmp = New-Object System.Drawing.Bitmap($S, $S)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
$rect = New-Object System.Drawing.Rectangle(0, 0, $S, $S)
$brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, [System.Drawing.Color]::FromArgb(255, 8, 14, 26), [System.Drawing.Color]::FromArgb(255, 18, 34, 58), 55.0)
$g.FillRectangle($brush, $rect)
$brush.Dispose()
Draw-Mark -G $g -Scale 1.25
$g.Dispose()
$bmp.Save($full, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()

# 2. Foreground: только знак на прозрачном. Scale 0.86 даёт ~61% холста —
#    крупнее прежних ~44%, но всё ещё внутри safe zone круговой маски.
$fgBmp = New-Object System.Drawing.Bitmap($S, $S)
$fg = [System.Drawing.Graphics]::FromImage($fgBmp)
$fg.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$fg.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
$fg.Clear([System.Drawing.Color]::Transparent)
Draw-Mark -G $fg -Scale 0.86
$fg.Dispose()
$foreground = Join-Path $OutDir 'icon_foreground.png'
$fgBmp.Save($foreground, [System.Drawing.Imaging.ImageFormat]::Png)
$fgBmp.Dispose()

# 3. Android: legacy mipmap и foreground adaptive icon по плотностям.
$densities = @(
    @{ Name = 'mdpi'; Mipmap = 48; Foreground = 108 },
    @{ Name = 'hdpi'; Mipmap = 72; Foreground = 162 },
    @{ Name = 'xhdpi'; Mipmap = 96; Foreground = 216 },
    @{ Name = 'xxhdpi'; Mipmap = 144; Foreground = 324 },
    @{ Name = 'xxxhdpi'; Mipmap = 192; Foreground = 432 }
)
foreach ($density in $densities) {
    Save-Resized -Source $full `
        -Destination (Join-Path $AndroidResDir "mipmap-$($density.Name)\ic_launcher.png") `
        -Size $density.Mipmap
    Save-Resized -Source $foreground `
        -Destination (Join-Path $AndroidResDir "drawable-$($density.Name)\ic_launcher_foreground.png") `
        -Size $density.Foreground
}

Write-Host "Готово:"
Write-Host "  $full"
Write-Host "  $foreground"
Write-Host "  Android: $AndroidResDir"
