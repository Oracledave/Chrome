<#
.SYNOPSIS
  Silently delete a target file and rename (move) a source file to that target name, with automatic elevation (UAC) if required.

.DESCRIPTION
  - This script is pre-configured to operate on the Chrome Cookies files for the user "Dave5":
      Target (to delete): C:\Users\Dave5\AppData\Local\Google\Chrome\User Data\Default\Network\Cookies
      Source (to rename): C:\Users\Dave5\AppData\Local\Google\Chrome\User Data\Default\Network\Cookies1
  - The script will require that all Chrome processes are closed before it proceeds. It will display a warning and wait until Chrome is fully closed; it will not continue until Chrome is closed.
  - After Chrome is closed, the script will restart itself elevated (showing the UAC prompt) if not already running as Administrator.
  - On success the script is silent and exits with code 0.
  - On error it writes an error message and returns a distinct non-zero exit code.

EXIT CODES
  0  = Success
  2  = Failed to delete existing target
  3  = Source file not found or invalid path
  4  = Failed to create target directory
  5  = Move/rename failed
  6  = Elevation cancelled or failed
#>

# Pre-configured paths
$Target = 'C:\Users\Dave5\AppData\Local\Google\Chrome\User Data\Default\Network\Cookies'
$Source = 'C:\Users\Dave5\AppData\Local\Google\Chrome\User Data\Default\Network\Cookies1'

function Abort([string]$message, [int]$code) {
    Write-Error $message
    exit $code
}

function Wait-ForChromeToExit {
    # Check for any running chrome processes and wait until none remain.
    while ($true) {
        $chromeProcs = Get-Process -Name chrome -ErrorAction SilentlyContinue
        if (-not $chromeProcs) { break }

        Write-Host ''
        Write-Host 'WARNING: Google Chrome appears to be running. Please close all Chrome windows and wait.' -ForegroundColor Yellow
        Write-Host 'The script will not continue until Chrome is fully closed.'
        Write-Host 'Running Chrome processes:'
        foreach ($p in $chromeProcs) {
            # Attempt to show a useful one-line per process
            $start = $null
            try { $start = $p.StartTime } catch { $start = '' }
            Write-Host ("  PID {0,-7}  Name {1,-15}  Started {2}" -f $p.Id, $p.ProcessName, $start)
        }
        Write-Host ''
        Write-Host 'Waiting 2 seconds before checking again... (Press Ctrl+C to cancel)' -ForegroundColor Gray
        Start-Sleep -Seconds 2
    }
}

# --- First: ensure Chrome is closed before even attempting elevation ---
try {
    Wait-ForChromeToExit
} catch {
    Abort "Interrupted while waiting for Chrome to close." 6
}

# --- Elevation: relaunch elevated if needed (do this AFTER Chrome is closed so user doesn't see UAC until ready) ---
try {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
} catch {
    $isAdmin = $false
}
if (-not $isAdmin) {
    try {
        $exePath = (Get-Process -Id $PID).Path
        $scriptPath = $PSCommandPath
        if (-not $scriptPath) { $scriptPath = $MyInvocation.MyCommand.Path }

        # Build argument list: -NoProfile -ExecutionPolicy Bypass -File <script>
        $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$scriptPath)
        Start-Process -FilePath $exePath -ArgumentList $argList -Verb RunAs -ErrorAction Stop
        # Original (unelevated) process exits; elevated instance will perform the work.
        exit 0
    } catch {
        Abort "Elevation cancelled or failed." 6
    }
}

# --- Normalize full paths ---
try {
    $fullTarget = [System.IO.Path]::GetFullPath($Target)
    $fullSource = [System.IO.Path]::GetFullPath($Source)
} catch {
    Abort "Invalid path(s) configured." 3
}

# If same path, nothing to do
if ($fullTarget.ToUpperInvariant() -eq $fullSource.ToUpperInvariant()) {
    exit 0
}

# Delete target if exists
if (Test-Path -LiteralPath $fullTarget) {
    try {
        Remove-Item -LiteralPath $fullTarget -Force -ErrorAction Stop
    } catch {
        Abort "ERROR: Failed to delete target file '$fullTarget'. It may be in use by another process." 2
    }
}

# Ensure source exists
if (-not (Test-Path -LiteralPath $fullSource)) {
    Abort "ERROR: Source file not found: '$fullSource'." 3
}

# Ensure target directory exists
$targetDir = Split-Path -Path $fullTarget -Parent
if (-not (Test-Path -LiteralPath $targetDir)) {
    try {
        New-Item -ItemType Directory -Path $targetDir -Force -ErrorAction Stop | Out-Null
    } catch {
        Abort "ERROR: Failed to create target directory '$targetDir'." 4
    }
}

# Move (rename) source to target (overwrite already handled by deletion)
try {
    Move-Item -LiteralPath $fullSource -Destination $fullTarget -Force -ErrorAction Stop
} catch {
    Abort "ERROR: Rename/Move failed: '$fullSource' -> '$fullTarget'. It may be in use by another process." 5
}

# Success: silent exit
exit 0
