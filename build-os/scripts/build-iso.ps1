<#
.SYNOPSIS
    AstraOS ISO Builder Helper Script for Windows
.DESCRIPTION
    Builds the AstraOS Bootable Live Linux ISO locally using WSL or Docker,
    or guides you on using GitHub Actions.
#>

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "             AstraOS Live ISO Build Helper                " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

$ProjectRoot = (Get-Item "$PSScriptRoot\..\..").FullName
Set-Location $ProjectRoot

# Step 1: Ensure Web Build is ready
Write-Host "[1/3] Checking AstraOS web build..." -ForegroundColor Yellow
if (-not (Test-Path "$ProjectRoot\build\index.html")) {
    Write-Host "Building AstraOS web application (npm run build)..." -ForegroundColor Gray
    cmd /c npm run build
    if (-not (Test-Path "$ProjectRoot\build\index.html")) {
        Write-Host "Error: Build failed. Please ensure 'npm run build' succeeds." -ForegroundColor Red
        Exit 1
    }
}
Write-Host "AstraOS web build verified in ./build" -ForegroundColor Green

# Step 2: Check for Docker or WSL
Write-Host ""
Write-Host "[2/3] Checking build environment..." -ForegroundColor Yellow

$hasDocker = $false
try {
    $null = docker --version 2>$null
    if ($LASTEXITCODE -eq 0) { $hasDocker = $true }
} catch {}

$hasWSL = $false
try {
    $wslDistros = wsl -l -q 2>$null
    if ($LASTEXITCODE -eq 0 -and $wslDistros.Count -gt 0) { $hasWSL = $true }
} catch {}

if ($hasDocker) {
    Write-Host "Docker detected! Building ISO via Docker..." -ForegroundColor Green
    if (-not (Test-Path "$ProjectRoot\output")) { New-Item -ItemType Directory -Path "$ProjectRoot\output" | Out-Null }
    docker build -f build-os/Dockerfile -t astraos-builder .
    docker run --privileged --rm -v "${ProjectRoot}/output:/output" astraos-builder
    Write-Host "ISO built successfully at $ProjectRoot\output\AstraOS-v1.0-x86_64.iso" -ForegroundColor Green
} elseif ($hasWSL) {
    Write-Host "WSL Linux environment detected! Building ISO via WSL..." -ForegroundColor Green
    # Convert windows path to wsl path
    $wslPath = (wsl wslpath -u "$ProjectRoot").Trim()
    wsl bash -c "cd '$wslPath' && sudo chmod +x build-os/build-iso.sh && sudo ./build-os/build-iso.sh"
    Write-Host "ISO build completed via WSL." -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "[!] Neither Docker nor a configured WSL distribution was detected on your PC." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Aapke paas ISO banane ke 2 aasan raste hain:" -ForegroundColor White
    Write-Host "  1. GitHub Actions (Sabse Easy, Free & Automatic):" -ForegroundColor Cyan
    Write-Host "     - Code ko GitHub par push karke 'Actions' tab par jaayein."
    Write-Host "     - 'Build AstraOS Bootable Live ISO' workflow chalaayein."
    Write-Host "     - Kuch hi minute me aapko direct 'AstraOS-v1.0-x86_64.iso' download mil jayegi!"
    Write-Host ""
    Write-Host "  2. Local WSL Setup:" -ForegroundColor Cyan
    Write-Host "     - PowerShell as Admin me run karein: wsl --install -d Ubuntu"
    Write-Host "     - Install hone ke baad dobara yeh script chalayein: .\build-os\scripts\build-iso.ps1"
    Write-Host ""
}
