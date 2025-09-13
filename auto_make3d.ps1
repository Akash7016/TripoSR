# auto_make3d.ps1  — single-image -> 3D (CPU-only) for Windows 11
param(
  [string]$img = "",
  [string]$out = ""
)

$ErrorActionPreference = "Stop"

# --- paths ---
$repo = "C:\ai3d\TripoSR"
$venv = Join-Path $repo ".venv\Scripts\Activate.ps1"

# --- ensure repo exists ---
if (-not (Test-Path $repo)) {
  New-Item -ItemType Directory -Force -Path "C:\ai3d" | Out-Null
  Set-Location "C:\ai3d"
  git clone https://github.com/VAST-AI-Research/TripoSR.git
}
Set-Location $repo

# --- ensure venv ---
if (-not (Test-Path $venv)) {
  py -3.10 -m venv .venv
}

# --- activate venv ---
. $venv

# --- first-run installs (idempotent) ---
pip install -U pip setuptools wheel scikit-build-core cmake ninja
# CPU PyTorch (stable on Win):
pip uninstall -y torch torchvision torchaudio | Out-Null
pip cache purge | Out-Null
pip install --index-url https://download.pytorch.org/whl/cpu torch torchvision torchaudio
# Windows-friendlier torchmcubes commit:
pip install --no-build-isolation --force-reinstall git+https://github.com/tatsy/torchmcubes.git@3aef8afa5f21b113afc4f4ea148baee850cbd472
# TripoSR deps + background removal
pip install -r requirements.txt
pip install rembg==2.0.67 onnxruntime==1.16.3

# --- locate image if not provided ---
if (-not $img -or -not (Test-Path $img)) {
  # try your known folder first
  $defaultDir = "D:\HackTheNorth\version 1.0"
  $candidate = $null
  if (Test-Path $defaultDir) {
    $candidate = Get-ChildItem $defaultDir -File -Include *.jpg,*.jpeg,*.png | Select-Object -First 1
  }
  if (-not $candidate) {
    $candidate = Get-ChildItem . -File -Include *.jpg,*.jpeg,*.png | Select-Object -First 1
  }
  if (-not $candidate) {
    Write-Error "No input image found. Pass -img <path-to-image> or put a .jpg/.png in '$defaultDir' or '$repo'."
  }
  $img = $candidate.FullName
}

# --- pick output dir (default: alongside image, folder 'output') ---
if (-not $out) {
  $imgDir = Split-Path $img -Parent
  $out = Join-Path $imgDir "output"
}
New-Item -ItemType Directory -Force -Path $out | Out-Null

# --- force CPU and run ---
$env:CUDA_VISIBLE_DEVICES = ""
python run.py "$img" --output-dir "$out" --bake-texture --texture-resolution 512

Write-Host "`n✅ Done. Outputs in: $out" -ForegroundColor Green
Write-Host "   Files: mesh.obj + texture(s)" -ForegroundColor Green
