# RemovePersistence.ps1 - Enhanced with verification
param(
    [Parameter(Mandatory=$false)]
    [switch]$Force,
    
    [Parameter(Mandatory=$false)]
    [switch]$VerifyOnly
)

# Configuration
$config = @{
    FolderPath = "C:\ProgramData\SecurityUpdate"
    TaskName = "SecurityUpdateTask"
    RegistryName = "SecurityUpdateService"
    RegistryPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
}

function Test-PersistenceExists {
    $results = @{
        Registry = $null -ne (Get-ItemProperty -Path $config.RegistryPath -Name $config.RegistryName -ErrorAction SilentlyContinue)
        Task = $null -ne (Get-ScheduledTask -TaskName $config.TaskName -ErrorAction SilentlyContinue)
        Folder = Test-Path $config.FolderPath
    }
    
    return $results
}

Write-Host "`n================================" -ForegroundColor Yellow
Write-Host "Persistence Removal Tool" -ForegroundColor Yellow
Write-Host "================================`n" -ForegroundColor Yellow

# Check what exists
Write-Host "[*] Scanning for persistence mechanisms...`n" -ForegroundColor Cyan
$existingItems = Test-PersistenceExists

# Display current state
Write-Host "Current Status:" -ForegroundColor Cyan

Write-Host "  Registry Key:     " -NoNewline
if ($existingItems.Registry) {
    Write-Host "FOUND" -ForegroundColor Red
    $regValue = Get-ItemProperty -Path $config.RegistryPath -Name $config.RegistryName -ErrorAction SilentlyContinue
    Write-Host "    Value: $($regValue.$($config.RegistryName))" -ForegroundColor Gray
} else {
    Write-Host "NOT FOUND" -ForegroundColor Green
}

Write-Host "  Scheduled Task:   " -NoNewline
if ($existingItems.Task) {
    Write-Host "FOUND" -ForegroundColor Red
    $task = Get-ScheduledTask -TaskName $config.TaskName -ErrorAction SilentlyContinue
    Write-Host "    State: $($task.State)" -ForegroundColor Gray
} else {
    Write-Host "NOT FOUND" -ForegroundColor Green
}

Write-Host "  Folder:           " -NoNewline
if ($existingItems.Folder) {
    Write-Host "FOUND" -ForegroundColor Red
    $folderSize = (Get-ChildItem -Path $config.FolderPath -Recurse -File | Measure-Object -Property Length -Sum).Sum
    Write-Host "    Size: $folderSize bytes" -ForegroundColor Gray
    Get-ChildItem -Path $config.FolderPath -File | ForEach-Object {
        Write-Host "    - $($_.Name)" -ForegroundColor Gray
    }
} else {
    Write-Host "NOT FOUND" -ForegroundColor Green
}

# If verify-only mode, exit here
if ($VerifyOnly) {
    Write-Host "`n================================`n" -ForegroundColor Yellow
    exit 0
}

# Check if anything needs to be removed
$needsRemoval = $existingItems.Registry -or $existingItems.Task -or $existingItems.Folder

if (-not $needsRemoval) {
    Write-Host "`n[+] No persistence mechanisms found. System is clean.`n" -ForegroundColor Green
    exit 0
}

# Confirmation
if (-not $Force) {
    Write-Host ""
    $response = Read-Host "Remove found items? (Y/N)"
    
    if ($response -ne 'Y' -and $response -ne 'y') {
        Write-Host "`n[!] Removal cancelled`n" -ForegroundColor Yellow
        exit 0
    }
}

Write-Host "`n[*] Beginning removal...`n" -ForegroundColor Cyan

# Remove registry
if ($existingItems.Registry) {
    Write-Host "[*] Removing registry key..." -ForegroundColor Cyan
    try {
        Remove-ItemProperty -Path $config.RegistryPath -Name $config.RegistryName -Force
        Write-Host "[+] Registry key removed" -ForegroundColor Green
    } catch {
        Write-Host "[X] Failed: $_" -ForegroundColor Red
    }
}

# Remove task
if ($existingItems.Task) {
    Write-Host "[*] Removing scheduled task..." -ForegroundColor Cyan
    try {
        Unregister-ScheduledTask -TaskName $config.TaskName -Confirm:$false
        Write-Host "[+] Scheduled task removed" -ForegroundColor Green
    } catch {
        Write-Host "[X] Failed: $_" -ForegroundColor Red
    }
}

# Remove files
if ($existingItems.Folder) {
    Write-Host "[*] Removing files and folder..." -ForegroundColor Cyan
    try {
        Remove-Item -Path $config.FolderPath -Recurse -Force
        Write-Host "[+] Files and folder removed" -ForegroundColor Green
    } catch {
        Write-Host "[X] Failed: $_" -ForegroundColor Red
    }
}

# Verify removal
Write-Host "`n[*] Verifying removal...`n" -ForegroundColor Cyan
$afterRemoval = Test-PersistenceExists

$allClean = -not ($afterRemoval.Registry -or $afterRemoval.Task -or $afterRemoval.Folder)

if ($allClean) {
    Write-Host "[+] SUCCESS: All persistence mechanisms removed!`n" -ForegroundColor Green
    exit 0
} else {
    Write-Host "[!] WARNING: Some items still present:" -ForegroundColor Yellow
    if ($afterRemoval.Registry) { Write-Host "  - Registry key" -ForegroundColor Red }
    if ($afterRemoval.Task) { Write-Host "  - Scheduled task" -ForegroundColor Red }
    if ($afterRemoval.Folder) { Write-Host "  - Folder" -ForegroundColor Red }
    Write-Host ""
    exit 1
}