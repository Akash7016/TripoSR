param(
  [Parameter(Mandatory=$true)][string]$img,
  [string]$out = ""
)

$ErrorActionPreference = "Stop"
$repo = "C:\ai3d\TripoSR"

# Basic checks + nice window title
if (-not (Test-Path $img)) { throw "Image not found: $img" }
$Host.UI.RawUI.WindowTitle = "TripoSR - " + (Split-Path $img -Leaf)

# Activate venv (assumes you've already set it up once)
. "$repo\.venv\Scripts\Activate.ps1"

# Pick output folder (default: alongside image)
if (-not $out) {
  $imgDir = Split-Path $img -Parent
  $out = Join-Path $imgDir "output"
}
New-Item -ItemType Directory -Force -Path $out | Out-Null

# Show clear progress messages
Write-Host "[*] Image: $img"
Write-Host "[*] Output: $out"
Write-Host "[*] Forcing CPU (stable on your setup)..."
$env:CUDA_VISIBLE_DEVICES = ""

# Run with unbuffered Python (-u) so logs stream live
Write-Host "[*] Running TripoSR... this may take a few minutes."
Set-Location $repo
try {
  & python -u run.py "$img" --output-dir "$out" --bake-texture --texture-resolution 512
  if ($LASTEXITCODE -ne 0) { throw "python exited with code $LASTEXITCODE" }
  Write-Host "`n✅ Done: $img" -ForegroundColor Green
  Write-Host "   Output: $out (mesh.obj + textures)" -ForegroundColor Green
}
catch {
  Write-Host "`n❌ Failed: $img" -ForegroundColor Red
  Write-Host $_.Exception.Message -ForegroundColor Red
  exit 1
}
