# Requires -RunAsAdministrator

# ============================================
# B2B - NTFS Full Control - Interactive PowerShell Script
# Ville Isoranta
# ============================================

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

    $output = & $Command 2>&1
    if ($Verbose) { $output | ForEach-Object { Write-Host $_ } }
    $output | Out-File -Append -FilePath $LogFile -Encoding UTF8


$currentUser    = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$totalStopwatch = [System.Diagnostics.Stopwatch]::new()
$stepStopwatch  = [System.Diagnostics.Stopwatch]::new()

Clear-Host
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  NTFS Permission Reset Script" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Running as : $currentUser" -ForegroundColor Gray
Write-Host "  Log File   : $logFile" -ForegroundColor Gray
Write-Host "  ACL Backup : $backupFile" -ForegroundColor Gray
Write-Host ""

# ---- Step A: Ask for target path ----
$targetPath = Read-Host "Enter the target folder path (e.g. F:\Users\julmuri)"
$targetPath = $targetPath.Trim('"').Trim("'").TrimEnd('\')

if (!(Test-Path $targetPath)) {
    Write-Host ""
    Write-Host "ERROR: Path does not exist: $targetPath" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

if (!(Test-Path $targetPath -PathType Container)) {
    Write-Host ""
    Write-Host "ERROR: Path is not a folder: $targetPath" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# ---- Step B: Ask about verbose output ----
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Output Options" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Y = Verbose output (show every file/folder as it is processed)"
Write-Host "  N = Quiet output (show progress per step only, faster)"
Write-Host ""
$verboseChoice = Read-Host "Do you want verbose output? (Y/N)"
$verbose = ($verboseChoice -eq "Y")

if ($verbose) {
    $quietFlag = @()
} else {
    $quietFlag = @("/Q")
}

# ---- Step C: Ask about ownership ----
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Ownership Options" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  1) Take ownership as the current user ($currentUser)"
Write-Host "  2) Take ownership as the Administrators group (BUILTIN\Administrators)"
Write-Host ""
$ownerChoice = Read-Host "Select ownership option (1 or 2)"

switch ($ownerChoice) {
    "1" {
        $takeownArgs = @("/F", $targetPath, "/R", "/D", "Y")
        $ownerDisplay = $currentUser
    }
    "2" {
        $takeownArgs = @("/F", $targetPath, "/R", "/A", "/D", "Y")
        $ownerDisplay = "BUILTIN\Administrators"
    }
    default {
        Write-Host "Invalid selection. Exiting." -ForegroundColor Red
        Read-Host "Press Enter to exit"
        exit 1
    }
}

# ---- Step D: Ask about Full Control principal ----
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Full Control Options" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  1) Grant Full Control to the current user ($currentUser)"
Write-Host "  2) Grant Full Control to the Administrators group (BUILTIN\Administrators)"
Write-Host "  3) Grant Full Control to a specific user or group"
Write-Host ""
$permChoice = Read-Host "Select Full Control option (1, 2, or 3)"

switch ($permChoice) {
    "1" {
        $principal = $currentUser
    }
    "2" {
        $principal = "BUILTIN\Administrators"
    }
    "3" {
        Write-Host ""
        $principal = Read-Host "Enter the user or group (e.g. DOMAIN\Username or BUILTIN\Users)"
        $principal = $principal.Trim()
        if ([string]::IsNullOrWhiteSpace($principal)) {
            Write-Host "No principal specified. Exiting." -ForegroundColor Red
            Read-Host "Press Enter to exit"
            exit 1
        }
    }
    default {
        Write-Host "Invalid selection. Exiting." -ForegroundColor Red
        Read-Host "Press Enter to exit"
        exit 1
    }
}

# ---- Step E: Ask about inheritance reset ----
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Inheritance Options" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Y = Wipe existing ACLs and re-inherit from parent (clean slate)" -ForegroundColor White
Write-Host "  N = Keep existing ACLs and just add Full Control on top (safer)" -ForegroundColor White
Write-Host ""
$resetInheritance = Read-Host "Do you want to reset inheritance? (Y/N)"

# ---- Count items ----
Write-Host ""
Write-Host "Counting files and folders, please wait..." -ForegroundColor Gray
$fileCount = (Get-ChildItem -Path $targetPath -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object).Count
$dirCount  = (Get-ChildItem -Path $targetPath -Recurse -Force -Directory -ErrorAction SilentlyContinue | Measure-Object).Count
$totalCount = $fileCount + $dirCount
Write-Host "Count complete." -ForegroundColor Gray

# ---- Confirm Summary ----
Write-Host ""
Write-Host "============================================" -ForegroundColor Yellow
Write-Host "  Summary - Please Confirm" -ForegroundColor Yellow
Write-Host "============================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Target Path       : $targetPath" -ForegroundColor White
Write-Host "  Folders           : $dirCount" -ForegroundColor White
Write-Host "  Files             : $fileCount" -ForegroundColor White
Write-Host "  Total Items       : $totalCount" -ForegroundColor White
Write-Host "  Verbose Output    : $(if ($verbose) {'YES'} else {'NO'})" -ForegroundColor White
Write-Host "  Ownership To      : $ownerDisplay" -ForegroundColor White
Write-Host "  Full Control To   : $principal" -ForegroundColor White
if ($resetInheritance -eq "Y") {
    Write-Host "  Reset Inheritance : YES (clean slate)" -ForegroundColor White
} else {
    Write-Host "  Reset Inheritance : NO (preserve existing ACLs)" -ForegroundColor White
}
Write-Host "  ACL Backup File   : $backupFile" -ForegroundColor White
Write-Host ""
$confirm = Read-Host "Proceed with these settings? (Y/N)"
if ($confirm -ne "Y") {
    Write-Host "Cancelled by user." -ForegroundColor Yellow
    exit 0
}

# ---- Start Total Timer ----
$totalStopwatch.Start()

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Starting..." -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

# ---- Step 1: Take Ownership ----
Write-Host ""
Write-Host "[Step 1/4] Taking ownership as $ownerDisplay..." -ForegroundColor Green
Write-Log "Step 1: Taking ownership of $targetPath as $ownerDisplay"
$stepStopwatch.Restart()

$output = & takeown @takeownArgs 2>&1
if ($verbose) { $output | ForEach-Object { Write-Host $_ } }
$output | Out-File -Append -FilePath $logFile -Encoding UTF8

$stepStopwatch.Stop()
$elapsed = Format-Elapsed $stepStopwatch
if ($LASTEXITCODE -eq 0) {
    Write-Log "Step 1: Ownership taken successfully - Elapsed: $elapsed"
    Write-Host "         Done. Elapsed: $elapsed" -ForegroundColor Gray
} else {
    Write-Log "Step 1: Completed with errors - Elapsed: $elapsed"
    Write-Host "         Completed with some errors. Elapsed: $elapsed | Check log." -ForegroundColor Yellow
}

# ---- Step 2: Backup ACLs (after ownership so we can read them) ----
Write-Host ""
Write-Host "[Step 2/4] Backing up current ACLs..." -ForegroundColor Green
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
    Write-Host "         Done. Backup: $backupSizeKB KB | Elapsed: $elapsed" -ForegroundColor Gray
} else {
    Write-Log "Step 2: ACL backup may have failed - Elapsed: $elapsed"
    Write-Host "         WARNING: Backup file not found. Check log." -ForegroundColor Yellow
}

# ---- Step 3: Grant Full Control ----
Write-Host ""
Write-Host "[Step 3/4] Granting Full Control to $principal..." -ForegroundColor Green
Write-Log "Step 3: Granting Full Control to $principal"
$stepStopwatch.Restart()

$output = & icacls $targetPath /grant "${principal}:(OI)(CI)F" /T /C @quietFlag 2>&1
if ($verbose) { $output | ForEach-Object { Write-Host $_ } }
$output | Out-File -Append -FilePath $logFile -Encoding UTF8

$stepStopwatch.Stop()
$elapsed = Format-Elapsed $stepStopwatch
if ($LASTEXITCODE -eq 0) {
    Write-Log "Step 3: Full Control granted successfully - Elapsed: $elapsed"
    Write-Host "         Done. Elapsed: $elapsed" -ForegroundColor Gray
} else {
    Write-Log "Step 3: Completed with errors - Elapsed: $elapsed"
    Write-Host "         Completed with some errors. Elapsed: $elapsed | Check log." -ForegroundColor Yellow
}

# ---- Step 4: Optional Inheritance Reset ----
if ($resetInheritance -eq "Y") {
    Write-Host ""
    Write-Host "[Step 4/4] Resetting inheritance on all child objects..." -ForegroundColor Green
    Write-Log "Step 4: Resetting inheritance"
    $stepStopwatch.Restart()

    $output = & icacls $targetPath /reset /T /C @quietFlag 2>&1
    if ($verbose) { $output | ForEach-Object { Write-Host $_ } }
    $output | Out-File -Append -FilePath $logFile -Encoding UTF8

    $stepStopwatch.Stop()
    $elapsed = Format-Elapsed $stepStopwatch
    Write-Log "Step 4: Inheritance reset completed - Elapsed: $elapsed"
    Write-Host "         Inheritance reset done. Elapsed: $elapsed" -ForegroundColor Gray

    Write-Host ""
    Write-Host "         Re-applying Full Control to $principal after reset..." -ForegroundColor Green
    Write-Log "Step 4b: Re-applying Full Control to $principal after reset"
    $stepStopwatch.Restart()

    $output = & icacls $targetPath /grant "${principal}:(OI)(CI)F" /T /C @quietFlag 2>&1
    if ($verbose) { $output | ForEach-Object { Write-Host $_ } }
    $output | Out-File -Append -FilePath $logFile -Encoding UTF8

    $stepStopwatch.Stop()
    $elapsed = Format-Elapsed $stepStopwatch
    Write-Log "Step 4b: Full Control re-applied - Elapsed: $elapsed"
    Write-Host "         Re-apply done. Elapsed: $elapsed" -ForegroundColor Gray
} else {
    Write-Host ""
    Write-Host "[Step 4/4] Skipping inheritance reset (existing ACLs preserved)." -ForegroundColor Yellow
    Write-Log "Step 4: Inheritance reset skipped by user"
}

# ---- Stop Total Timer ----
$totalStopwatch.Stop()
$totalElapsed = Format-Elapsed $totalStopwatch

# ---- Finished ----
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Complete!" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Total Elapsed  : $totalElapsed" -ForegroundColor White
Write-Host "  Log File       : $logFile" -ForegroundColor White
Write-Host "  ACL Backup     : $backupFile" -ForegroundColor White
Write-Host ""

# ---- Ask about restore ----
Write-Host "============================================" -ForegroundColor Yellow
Write-Host "  Restore Option" -ForegroundColor Yellow
Write-Host "============================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "  If something went wrong, you can restore the original ACLs" -ForegroundColor White
Write-Host "  from the backup taken after ownership was established." -ForegroundColor White
Write-Host ""
$restoreChoice = Read-Host "Do you want to restore the original ACLs from backup? (Y/N)"

if ($restoreChoice -eq "Y") {
    $parentPath = Split-Path $targetPath -Parent
    Write-Host ""
    Write-Host "Restoring ACLs from $backupFile..." -ForegroundColor Green
    Write-Log "Restore: Restoring ACLs from $backupFile to $parentPath"
    $stepStopwatch.Restart()

    $output = & icacls $parentPath /restore $backupFile /C @quietFlag 2>&1
    if ($verbose) { $output | ForEach-Object { Write-Host $_ } }
    $output | Out-File -Append -FilePath $logFile -Encoding UTF8

    $stepStopwatch.Stop()
    $elapsed = Format-Elapsed $stepStopwatch
    if ($LASTEXITCODE -eq 0) {
        Write-Log "Restore: ACLs restored successfully - Elapsed: $elapsed"
        Write-Host "         ACLs restored successfully. Elapsed: $elapsed" -ForegroundColor Green
    } else {
        Write-Log "Restore: Completed with errors - Elapsed: $elapsed"
        Write-Host "         Restore completed with errors. Elapsed: $elapsed | Check log." -ForegroundColor Yellow
    }
} else {
    $parentPath = Split-Path $targetPath -Parent
    $restoreCmd = "icacls `"$parentPath`" /restore `"$backupFile`" /C"

    Write-Log "Restore: User declined restore."
    Write-Log "Restore: Backup file saved at $backupFile"
    Write-Log "Restore: Manual restore command: $restoreCmd"

    Write-Host ""
    Write-Host "  No restore performed. Your backup file is saved at:" -ForegroundColor Gray
    Write-Host "  $backupFile" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  To manually restore later, run:" -ForegroundColor Gray
    Write-Host "  $restoreCmd" -ForegroundColor White
}
# } else {
#   Write-Host ""
#    Write-Host "  No restore performed. Your backup file is saved at:" -ForegroundColor Gray
#    Write-Host "  $backupFile" -ForegroundColor Gray
#    Write-Host ""
#    Write-Host "  To manually restore later, run:" -ForegroundColor Gray
#    $parentPath = Split-Path $targetPath -Parent
#    Write-Host "  icacls `"$parentPath`" /restore `"$backupFile`" /C" -ForegroundColor White
#}

Write-Host ""
Read-Host "Press Enter to exit"