#Requires -RunAsAdministrator

# ============================================
# Full Control - Non-Interactive PowerShell Script
# 
# B2B Solutions Oy
# Ville Isoranta
# Configure all options in the section below,
# then run the script. No prompts will appear.
# ============================================

# ==================== USER CONFIGURATION ====================

# Target folder path (e.g. "F:\Users\julmuri")
$targetPath = "F:\Users\julmuri"

# Verbose output: $true = show every file/folder as processed, $false = quiet (faster)
$verbose = $false

# Ownership option:
#   "CurrentUser"    = Take ownership as the current logged-in user
#   "Administrators" = Take ownership as BUILTIN\Administrators
$ownershipOption = "Administrators"

# Full Control principal: who gets Full Control over the target path
# Examples: "BUILTIN\Administrators", "DOMAIN\Username", "BUILTIN\Users"
# Leave blank to use the current logged-in user.
$principal = ""

# Reset inheritance: $true = wipe existing ACLs and re-inherit from parent (clean slate)
#                    $false = keep existing ACLs and just add Full Control on top (safer)
$resetInheritance = $false

# ==================== END USER CONFIGURATION ================

# Setup logging
$logDir = "C:\Temp"
if (!(Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
$timestamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
$logFile    = Join-Path $logDir "PermissionsFix_$timestamp.log"
$backupFile = Join-Path $logDir "PermissionsFix_ACL_Backup_$timestamp.txt"

function Write-Log {
    param([string]$Message)
    $entry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message"
    Write-Host $entry
    Add-Content -Path $logFile -Value $entry -Encoding UTF8
}

function Format-Elapsed {
    param([System.Diagnostics.Stopwatch]$sw)
    $ts = $sw.Elapsed
    if ($ts.TotalMinutes -ge 1) {
        return "{0:00}m {1:00}s" -f [math]::Floor($ts.TotalMinutes), $ts.Seconds
    } else {
        return "{0:00}s {1:000}ms" -f $ts.Seconds, $ts.Milliseconds
    }
}

$currentUser    = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$totalStopwatch = [System.Diagnostics.Stopwatch]::new()
$stepStopwatch  = [System.Diagnostics.Stopwatch]::new()

# ---- Validate target path ----
$targetPath = $targetPath.Trim('"').Trim("'").TrimEnd('\')

if (!(Test-Path $targetPath)) {
    Write-Host "ERROR: Path does not exist: $targetPath" -ForegroundColor Red
    exit 1
}

if (!(Test-Path $targetPath -PathType Container)) {
    Write-Host "ERROR: Path is not a folder: $targetPath" -ForegroundColor Red
    exit 1
}

# ---- Resolve ownership option ----
switch ($ownershipOption) {
    "CurrentUser" {
        $takeownArgs = @("/F", $targetPath, "/R", "/D", "Y")
        $ownerDisplay = $currentUser
    }
    "Administrators" {
        $takeownArgs = @("/F", $targetPath, "/R", "/A", "/D", "Y")
        $ownerDisplay = "BUILTIN\Administrators"
    }
    default {
        Write-Host "ERROR: Invalid ownershipOption '$ownershipOption'. Use 'CurrentUser' or 'Administrators'."
        exit 1
    }
}

# ---- Resolve Full Control principal ----
if ([string]::IsNullOrWhiteSpace($principal)) {
    $principal = $currentUser
}

# ---- Resolve quiet flag ----
if ($verbose) {
    $quietFlag = @()
} else {
    $quietFlag = @("/Q")
}

# ---- Start Total Timer ----
$totalStopwatch.Start()

# ---- Step 1: Take Ownership ----
Write-Log "Step 1: Taking ownership of $targetPath as $ownerDisplay"
$stepStopwatch.Restart()

$output = & takeown @takeownArgs 2>&1
if ($verbose) { $output | ForEach-Object { Write-Host $_ } }
$output | Out-File -Append -FilePath $logFile -Encoding UTF8

$stepStopwatch.Stop()
$elapsed = Format-Elapsed $stepStopwatch
if ($LASTEXITCODE -eq 0) {
    Write-Log "Step 1: Completed - Elapsed: $elapsed"
    Write-Host "         Done. Elapsed: $elapsed"
} else {
    Write-Log "Step 1: Completed with errors - Elapsed: $elapsed"
    Write-Host "         Completed with errors. Elapsed: $elapsed | Check log."
}

# ---- Count items ----
$fileCount  = (Get-ChildItem -Path $targetPath -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object).Count
$dirCount   = (Get-ChildItem -Path $targetPath -Recurse -Force -Directory -ErrorAction SilentlyContinue | Measure-Object).Count
$totalCount = $fileCount + $dirCount

# ---- Step 2: Backup ACLs ----
Write-Log "Step 2: Backing up ACLs to $backupFile"
$stepStopwatch.Restart()

$output = & icacls $targetPath /save $backupFile /T /C 2>&1
if ($verbose) { $output | ForEach-Object { Write-Host $_ } }
$output | Out-File -Append -FilePath $logFile -Encoding UTF8

$stepStopwatch.Stop()
$elapsed = Format-Elapsed $stepStopwatch
if (Test-Path $backupFile) {
    $backupSize   = (Get-Item $backupFile).Length
    $backupSizeKB = [math]::Round($backupSize / 1KB, 1)
    Write-Log "Step 2: ACL backup completed ($backupSizeKB KB) - Elapsed: $elapsed"
    Write-Host "         Done. Backup: $backupSizeKB KB | Elapsed: $elapsed" 
} else {
    Write-Log "Step 2: ACL backup may have failed - Elapsed: $elapsed"
    Write-Host "         WARNING: Backup file not found. Check log." 
}

# ---- Step 3: Grant Full Control ----
Write-Log "Step 3: Granting Full Control to $principal"
$stepStopwatch.Restart()

$output = & icacls $targetPath /grant "${principal}:(OI)(CI)F" /T /C @quietFlag 2>&1
if ($verbose) { $output | ForEach-Object { Write-Host $_ } }
$output | Out-File -Append -FilePath $logFile -Encoding UTF8

$stepStopwatch.Stop()
$elapsed = Format-Elapsed $stepStopwatch
if ($LASTEXITCODE -eq 0) {
    Write-Log "Step 3: Full Control granted successfully - Elapsed: $elapsed"
    Write-Host "         Done. Elapsed: $elapsed" 
} else {
    Write-Log "Step 3: Completed with errors - Elapsed: $elapsed"
    Write-Host "         Completed with some errors. Elapsed: $elapsed | Check log."
}

# ---- Step 4: Optional Inheritance Reset ----
if ($resetInheritance) {
    Write-Log "Step 4: Resetting inheritance"
    $stepStopwatch.Restart()

    $output = & icacls $targetPath /reset /T /C @quietFlag 2>&1
    if ($verbose) { $output | ForEach-Object { Write-Host $_ } }
    $output | Out-File -Append -FilePath $logFile -Encoding UTF8

    $stepStopwatch.Stop()
    $elapsed = Format-Elapsed $stepStopwatch
    Write-Log "Step 4: Inheritance reset completed - Elapsed: $elapsed"
    Write-Host "         Inheritance reset done. Elapsed: $elapsed" 

    Write-Host ""
    Write-Host "         Re-applying Full Control to $principal after reset..."
    Write-Log "Step 4b: Re-applying Full Control to $principal after reset"
    $stepStopwatch.Restart()

    $output = & icacls $targetPath /grant "${principal}:(OI)(CI)F" /T /C @quietFlag 2>&1
    if ($verbose) { $output | ForEach-Object { Write-Host $_ } }
    $output | Out-File -Append -FilePath $logFile -Encoding UTF8

    $stepStopwatch.Stop()
    $elapsed = Format-Elapsed $stepStopwatch
    Write-Log "Step 4b: Full Control re-applied - Elapsed: $elapsed"
    Write-Host "         Re-apply done. Elapsed: $elapsed" 
} else {
    Write-Host ""
    Write-Host "[Step 4] Skipping inheritance reset (existing ACLs preserved)."
    Write-Log "Step 4: Inheritance reset skipped per configuration"
}

# ---- Stop Total Timer ----
$totalStopwatch.Stop()
$totalElapsed = Format-Elapsed $totalStopwatch

# ---- Finished ----
$parentPath = Split-Path $targetPath -Parent
$restoreCmd = "icacls `"$parentPath`" /restore `"$backupFile`" /C"

Write-Host ""
Write-Host "============================================"
Write-Host "  Complete!"
Write-Host "============================================"
Write-Host ""
Write-Host "  Total Elapsed  : $totalElapsed"
Write-Host "  Log File       : $logFile"
Write-Host "  ACL Backup     : $backupFile"
Write-Log "  Total Elapsed  : $totalElapsed"
Write-Log "  Log File       : $logFile"
Write-Log "  ACL Backup     : $backupFile"
Write-Host "  Items Processed : $totalCount ($fileCount files, $dirCount folders)"
Write-Log  "  Items Processed : $totalCount ($fileCount files, $dirCount folders)"
Write-Host ""
Write-Host "  To restore original ACLs if needed, run:"
Write-Host "  $restoreCmd"
Write-Host ""

Write-Log "Script completed. Total elapsed: $totalElapsed"
Write-Log "Restore command: $restoreCmd"