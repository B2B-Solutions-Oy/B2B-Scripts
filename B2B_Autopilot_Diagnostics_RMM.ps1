# ============================================================
# MDM / Autopilot Diagnostics Collection Script (Non-Interactive)
# ============================================================
[CmdletBinding()]
param(
    # Set to $false to skip the Community Autopilot Diagnostics step
    [bool]$RunCommunity = $true,

    # Optional override for the Autopilot script path
    [string]$AutopilotScriptPath = (Join-Path $PSScriptRoot "Get-AutopilotDiagnosticsCommunity.ps1")
)

Write-Host ""
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host " MDM / Autopilot Diagnostics" -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host ""

# ---- Step 1: Gather system info up front ----
$serial   = (Get-WmiObject Win32_BIOS).SerialNumber.Trim()
$datetime = Get-Date -Format "yyyy-MM-dd_HH-mm"
$day      = Get-Date -Format "yyyy-MM-dd"

# ---- Output folder: DAY_SERIAL ----
$outputDir = Join-Path $PSScriptRoot "$($day)_$($serial)"
if (-not (Test-Path $outputDir)) {
    New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
}

$baseName = "$($serial)_$($datetime)"
$zipFile  = Join-Path $outputDir "$($baseName)_MDMDiagReport.zip"
$logFile  = Join-Path $outputDir "$($baseName)_APDiagnostics.log"
$apScript = $AutopilotScriptPath

Write-Host ""
Write-Host " Serial:      $serial"
Write-Host " Timestamp:   $datetime"
Write-Host " Output dir:  $outputDir"
Write-Host " Zip file:    $zipFile"
Write-Host " Log file:    $logFile"
Write-Host ""

# ---- Step 2: Community Autopilot Diagnostics ----
if ($RunCommunity) {

    if (-not (Test-Path $apScript)) {
        Write-Host "Could not find Get-AutopilotDiagnosticsCommunity.ps1 at: $apScript" -ForegroundColor Red
    } else {
        Write-Host ""
        Write-Host "Running: $apScript" -ForegroundColor Yellow
        Write-Host "Logging output to: $logFile" -ForegroundColor DarkGray
        Write-Host "-------------------------------------------" -ForegroundColor DarkGray

        # Header in log
        "===========================================" | Out-File -FilePath $logFile -Encoding UTF8
        "Autopilot Diagnostics (Community)"            | Out-File -FilePath $logFile -Append -Encoding UTF8
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

        # ---- Append ipconfig /all to the same log ----
        Write-Host "Collecting ipconfig /all ..." -ForegroundColor Yellow

        ""                                             | Out-File -FilePath $logFile -Append -Encoding UTF8
        "===========================================" | Out-File -FilePath $logFile -Append -Encoding UTF8
        "ipconfig /all"                                | Out-File -FilePath $logFile -Append -Encoding UTF8
        "===========================================" | Out-File -FilePath $logFile -Append -Encoding UTF8

        try {
            & ipconfig /all *>&1 | Tee-Object -FilePath $logFile -Append
        } catch {
            $err = "Failed to run ipconfig: $($_.Exception.Message)"
            Write-Host $err -ForegroundColor Red
            $err | Out-File -FilePath $logFile -Append -Encoding UTF8
        }

        Write-Host "-------------------------------------------" -ForegroundColor DarkGray
        Write-Host "Log saved to: $logFile" -ForegroundColor Green
    }
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
    Write-Host "MDM report saved to:" -ForegroundColor Green
    Write-Host "  $zipFile" -ForegroundColor Green
} else {
    Write-Host "Something went wrong - the zip file was not created." -ForegroundColor Red
}
if (Test-Path $logFile) {
    Write-Host "Autopilot log saved to:" -ForegroundColor Green
    Write-Host "  $logFile" -ForegroundColor Green
}
Write-Host ""
Write-Host "Done." -ForegroundColor Cyan