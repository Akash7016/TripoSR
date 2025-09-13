# launch_picker.ps1 — double-click friendly launcher + file picker + live logs
# Location: C:\ai3d\TripoSR\launch_picker.ps1

param(
    [Parameter(Mandatory=$false)]
    [string[]]$files = @()    # optional; if empty we show a file picker
)

# If the .bat passed raw args but not into -files, pick them up:
if ($files.Count -eq 0 -and $args.Count -gt 0) {
    $files = @($args)
}

# Relaunch in STA if needed (picker requires STA)
if ($host.Runspace.ApartmentState -ne 'STA') {
    Start-Process -FilePath "powershell.exe" -ArgumentList @(
        "-NoLogo","-NoProfile","-ExecutionPolicy","Bypass","-STA","-NoExit",
        "-File", "`"$PSCommandPath`""
    ) -Wait
    exit
}

$ErrorActionPreference = "Stop"
$repo   = "C:\ai3d\TripoSR"
$runner = Join-Path $repo "run_fast.ps1"

# Sanity checks
if (-not (Test-Path $repo))   { Write-Host "❌ Repo folder missing: $repo" -ForegroundColor Red; Read-Host "Press ENTER to close"; exit 1 }
if (-not (Test-Path $runner)) { Write-Host "❌ Runner missing: $runner"   -ForegroundColor Red; Read-Host "Press ENTER to close"; exit 1 }

function Process-Image([string]$imgPath) {
    try {
        if (-not (Test-Path $imgPath)) { Write-Host "❌ Not found: $imgPath" -ForegroundColor Red; return }
        Write-Host "[>] Processing: $imgPath" -ForegroundColor Cyan

        # Call the worker; it activates venv and streams logs with python -u
        & powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File $runner -img $imgPath
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Done: $imgPath" -ForegroundColor Green
        } else {
            Write-Host "❌ Failed (exit $LASTEXITCODE): $imgPath" -ForegroundColor Red
        }
    } catch {
        Write-Host "❌ Error: $($_.Exception.Message)" -ForegroundColor Red
    }
    Write-Host ""
}

# If no files provided (double-click), open a file picker
if ($files.Count -eq 0) {
    Add-Type -AssemblyName System.Windows.Forms
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title       = "Select JPG/PNG images"
    $dlg.Filter      = "Images|*.jpg;*.jpeg;*.png"
    $dlg.Multiselect = $true

    $result = $dlg.ShowDialog()
    if ($result -ne [System.Windows.Forms.DialogResult]::OK -or $dlg.FileNames.Count -eq 0) {
        Write-Host "[!] No file selected. Exiting..."
        Read-Host "Press ENTER to close"
        exit
    }
    $files = $dlg.FileNames
}

# Process all provided (or selected) files
foreach ($f in $files) { Process-Image $f }

Write-Host "✅ All done." -ForegroundColor Green
Read-Host "Press ENTER to close"
