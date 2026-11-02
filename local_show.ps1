<#
.SYNOPSIS
    Проигрывает ASCII-фильм (2.txt) прямо в консоли Windows.
.DESCRIPTION
    Локальный плеер для формата ascii-telnet-server:
    1 заголовок задержки + 13 строк кадра, 15 fps по умолчанию.
.PARAMETER MovieFile
    Путь к файлу фильма. По умолчанию "2.txt" рядом со скриптом.
.PARAMETER Fps
    Скорость. По умолчанию 15.
.EXAMPLE
    .\play-ascii-movie.ps1
.EXAMPLE
    .\play-ascii-movie.ps1 -MovieFile "2.txt" -Fps 20
#>
#Requires -Version 5.0
param(
    [string]$MovieFile = "",
    [int]$Fps = 15
)

if ($Fps -lt 1)  { $Fps = 1 }
if ($Fps -gt 60) { $Fps = 60 }

# --- resolve movie file -----------------------------------------------------
if ([string]::IsNullOrEmpty($MovieFile)) {
    $baseDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    $MovieFile = Join-Path $baseDir "sw1.txt"
}
if (-not (Test-Path -LiteralPath $MovieFile)) {
    Write-Host "Movie file not found: $MovieFile" -ForegroundColor Red
    Write-Host "Usage: play-ascii-movie.ps1 [-MovieFile path\to\sw1.txt] [-Fps 15]" -ForegroundColor Yellow
    exit 1
}
$MovieFile = (Resolve-Path -LiteralPath $MovieFile).Path

# --- read file --------------------------------------------------------------
try   { $encoding = [System.Text.Encoding]::GetEncoding("iso-8859-15") }
catch { $encoding = [System.Text.Encoding]::GetEncoding(1252) }

$allLines = [System.IO.File]::ReadAllLines($MovieFile, $encoding)

# --- parse frames (mirror of VT100Player/Movie in python) -------------------
$movieWidth    = 67
$movieHeight   = 13
$linesPerBlock = 14          # 1 header + 13 content

$frames       = New-Object System.Collections.ArrayList
$currentFrame = $null
$counter      = 0

foreach ($line in $allLines) {
    $delay = -1
    if (($counter % $linesPerBlock) -eq 0 -and $line.Length -gt 0) {
        $head = $line.Substring(0, [Math]::Min(3, $line.Length)).Trim()
        if ($head.Length -gt 0) {
            $parsed = 0
            if ([int]::TryParse($head, [ref]$parsed)) { $delay = $parsed }
        }
    }

    $stripped = $line.Trim()
    if ($stripped.Length -le 3 -and $delay -gt 0 -and $delay -le 999) {
        $currentFrame = [PSCustomObject]@{
            Delay = $delay
            Data  = (New-Object System.Collections.ArrayList)
        }
        [void]$frames.Add($currentFrame)
    }
    elseif ($null -ne $currentFrame) {
        $row = $line.TrimEnd()
        if ($row.Length -lt $movieWidth) { $row = $row.PadRight($movieWidth) }
        [void]$currentFrame.Data.Add($row)
    }

    $counter++
}

if ($frames.Count -eq 0) {
    Write-Host "No frames parsed. Wrong file format?" -ForegroundColor Red
    exit 1
}

$totalTicks = 0
foreach ($f in $frames) { $totalTicks += $f.Delay }

Write-Host ""
Write-Host "Movie : $MovieFile" -ForegroundColor Cyan
Write-Host "Frames: $($frames.Count)   Ticks: $totalTicks   FPS: $Fps" -ForegroundColor Cyan
Write-Host "Start in 3s... (Ctrl+C to abort)" -ForegroundColor Yellow
Start-Sleep -Seconds 3

# --- save / restore console state ------------------------------------------
$savedCursor = $true
try { $savedCursor = [Console]::CursorVisible } catch {}
$savedTitle = $null
try { $savedTitle = $Host.UI.RawUI.WindowTitle } catch {}

try {
    try { [Console]::CursorVisible = $false } catch {}
    try { $Host.UI.RawUI.WindowTitle = "ASCII Movie Player" } catch {}
    [Console]::Clear()

    $currentPos = 0

    foreach ($frame in $frames) {
        $currentPos += $frame.Delay

        # динамические размеры консоли (учёт ресайза)
        $winW = 80; $winH = 24
        try {
            $winW = [Console]::WindowWidth
            $winH = [Console]::WindowHeight
        } catch {}

        $offX = [Math]::Max(0, [int](($winW - $movieWidth) / 2))
        $offY = [Math]::Max(0, [int](($winH - 1 - $movieHeight) / 2))
        $barY = [Math]::Max(0, $winH - 1)

        # --- кадр -----------------------------------------------------------
        $rowIdx = 0
        foreach ($row in $frame.Data) {
            if ($rowIdx -ge $movieHeight) { break }
            $y = $offY + $rowIdx
            if ($y -ge 0 -and $y -lt $winH) {
                $maxLen = $winW - $offX
                if ($maxLen -gt 0) {
                    $text = if ($row.Length -gt $maxLen) { $row.Substring(0, $maxLen) } else { $row }
                    try {
                        [Console]::SetCursorPosition($offX, $y)
                        [Console]::Write($text)
                    } catch {}
                }
            }
            $rowIdx++
        }

        # --- таймбар --------------------------------------------------------
        try {
            $barWidth = [Math]::Max(10, $winW - 4)
            $body = ("." * $barWidth).ToCharArray()
            $ratio = if ($totalTicks -gt 1) {
                [Math]::Min(1.0, $currentPos / [double]($totalTicks - 1))
            } else { 0.0 }
            $barPos = [int]($ratio * ($barWidth - 1))
            if ($barPos -lt 0)          { $barPos = 0 }
            if ($barPos -ge $barWidth)  { $barPos = $barWidth - 1 }
            $body[$barPos] = 'o'
            $barText = " <" + (-join $body) + ">"
            if ($barText.Length -gt $winW) { $barText = $barText.Substring(0, $winW) }
            [Console]::SetCursorPosition(0, $barY)
            [Console]::Write($barText)
        } catch {}

        # --- пауза ----------------------------------------------------------
        $ms = [int](1000.0 * $frame.Delay / $Fps)
        if ($ms -gt 0) { Start-Sleep -Milliseconds $ms }
    }

    try { [Console]::SetCursorPosition(0, [Math]::Max(0, $winH - 1)) } catch {}
    Write-Host ""
    Write-Host "=== The End ===" -ForegroundColor Green
}
finally {
    try { [Console]::CursorVisible = $savedCursor } catch {}
    if ($savedTitle) {
        try { $Host.UI.RawUI.WindowTitle = $savedTitle } catch {}
    }
}
