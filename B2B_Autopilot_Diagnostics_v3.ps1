# ============================================================
# MDM / Autopilot Diagnostics Collection Script
# ============================================================
Write-Host ""
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host " MDM / Autopilot Diagnostics" -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host ""

# ---- Step 1: Gather user + system info up front ----
$userName = Read-Host "Enter the user's name"
$userName = $userName -replace '[\\/:*?"<>|]', '' -replace '\s+', '_'

$serial   = (Get-WmiObject Win32_BIOS).SerialNumber.Trim()
$datetime = Get-Date -Format "yyyy-MM-dd_HH-mm"
$day      = Get-Date -Format "yyyy-MM-dd"

# ---- Output folder: DAY_SERIAL ----
$outputDir = Join-Path $PSScriptRoot "$($day)_$($username)_$($serial)"
if (-not (Test-Path $outputDir)) {
    New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
}

$baseName = "$($userName)_$($serial)_$($datetime)"
$zipFile  = Join-Path $outputDir "$($baseName)_MDMDiagReport.zip"
$logFile  = Join-Path $outputDir "$($baseName)_APDiagnostics.log"
$apScript = Join-Path $PSScriptRoot "Get-AutopilotDiagnosticsCommunity.ps1"

Write-Host ""
Write-Host " User:        $userName"
Write-Host " Serial:      $serial"
Write-Host " Timestamp:   $datetime"
Write-Host " Output dir:  $outputDir"
Write-Host " Zip file:    $zipFile"
Write-Host " Log file:    $logFile"
Write-Host ""

# ---- Step 2: Community Autopilot Diagnostics ----
$runCommunity = Read-Host "Run Community Autopilot Diagnostics first? (Y/N)"
if ($runCommunity -match '^(y|yes)$') {

    if (-not (Test-Path $apScript)) {
        Write-Host "Could not find Get-AutopilotDiagnosticsCommunity.ps1 in: $PSScriptRoot" -ForegroundColor Red
        Write-Host "Download Get-AutopilotDiagnosticsCommunity.ps1, opening browser..."
        Start-process "https://github.com/andrew-s-taylor/WindowsAutopilotInfo/blob/main/Community%20Version%2FGet-AutopilotDiagnosticsCommunity.ps1"
        Write-Host "Close window and run script again after download if you wish to run ALL diagnostics. Waiting 5 seconds..."
        Start-Sleep -Seconds 5
        Write-Host ""
        Write-Host "Running: $apScript" -ForegroundColor Yellow
        Write-Host "Logging output to: $logFile" -ForegroundColor DarkGray
        Write-Host "-------------------------------------------" -ForegroundColor DarkGray

        # Header in log
        "===========================================" | Out-File -FilePath $logFile -Encoding UTF8
        "Autopilot Diagnostics (Community)"            | Out-File -FilePath $logFile -Append -Encoding UTF8
        "User:      $userName"                         | Out-File -FilePath $logFile -Append -Encoding UTF8
        "Serial:    $serial"                           | Out-File -FilePath $logFile -Append -Encoding UTF8
        "Timestamp: $datetime"                         | Out-File -FilePath $logFile -Append -Encoding UTF8
        "Script:    $apScript"                         | Out-File -FilePath $logFile -Append -Encoding UTF8
        "===========================================" | Out-File -FilePath $logFile -Append -Encoding UTF8
        ""                                             | Out-File -FilePath $logFile -Append -Encoding UTF8

        try {
            & $apScript *>&1 | Tee-Object -FilePath $logFile -Append
        } catch {
            $err = "Failed to run: $($_.Exception.Message)"
            Write-Host $err -ForegroundColor Red
            $err | Out-File -FilePath $logFile -Append -Encoding UTF8
        }

        # ---- Append dsregcmd /status to the same log ----
        Write-Host ""
        Write-Host "Collecting dsregcmd /status ..." -ForegroundColor Yellow

        ""                                             | Out-File -FilePath $logFile -Append -Encoding UTF8
        "===========================================" | Out-File -FilePath $logFile -Append -Encoding UTF8
        "dsregcmd /status"                             | Out-File -FilePath $logFile -Append -Encoding UTF8
        "===========================================" | Out-File -FilePath $logFile -Append -Encoding UTF8

        try {
            & dsregcmd.exe /status *>&1 | Tee-Object -FilePath $logFile -Append
        } catch {
            $err = "Failed to run dsregcmd: $($_.Exception.Message)"
            Write-Host $err -ForegroundColor Red
            $err | Out-File -FilePath $logFile -Append -Encoding UTF8
        }

         try {
            & ipconfig /all *>&1 | Tee-Object -FilePath $logFile -Append
        } catch {
            $err = "Failed to run ipconfig: $($_.Exception.Message)"
            Write-Host $err -ForegroundColor Red
            $err | Out-File -FilePath $logFile -Append -Encoding UTF8
        }
        Start-Sleep -Seconds 5
        Write-Host "-------------------------------------------" -ForegroundColor DarkGray
        Write-Host "Log saved to: $logFile" -ForegroundColor Green
    }

    Write-Host ""
    Read-Host "Press Enter to continue with MDM diagnostics"
}

# ---- Step 3: Run MDM diagnostics tool ----
Write-Host ""
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host " MDM Diagnostics Collection" -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host " Output file: $zipFile"
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Running mdmdiagnosticstool.exe ..." -ForegroundColor Yellow
Write-Host ""

& mdmdiagnosticstool.exe -area "DeviceEnrollment;DeviceProvisioning;Autopilot" -zip "$zipFile" | Out-Host

Write-Host ""
if (Test-Path $zipFile) {
    Write-Host "✔ MDM report saved to:" -ForegroundColor Green
    Write-Host "  $zipFile" -ForegroundColor Green
} else {
    Write-Host "✖ Something went wrong — the zip file was not created." -ForegroundColor Red
}
if (Test-Path $logFile) {
    Write-Host "✔ Autopilot log saved to:" -ForegroundColor Green
    Write-Host "  $logFile" -ForegroundColor Green
}
Write-Host ""
Read-Host "Press Enter to close"
