<#
after_model_auto.ps1  — Python-only OBJ->GLB + viewers with exact phone URLs

Usage:
powershell -ExecutionPolicy Bypass -File "C:\ai3d\TripoSR\after_model_auto.ps1" -outDir "C:\ai3d\TripoSR\output\<job>\0"
#>

param(
  [Parameter(Mandatory=$true)]
  [string]$outDir
)

$ErrorActionPreference = "Stop"

function Write-Info($m){ Write-Host $m -ForegroundColor Cyan }
function Write-OK($m){ Write-Host $m -ForegroundColor Green }
function Write-Warn($m){ Write-Host $m -ForegroundColor Yellow }
function Write-Err($m){ Write-Host $m -ForegroundColor Red }

if (-not (Test-Path $outDir)) { Write-Err "Output dir not found: $outDir"; Read-Host "Press ENTER to close"; exit 1 }

# ---------- [1/5] Ensure MTL + link texture ----------
Write-Info "[1/5] Ensuring MTL + linking texture"

# Find OBJ
$obj = Join-Path $outDir "mesh.obj"
if (-not (Test-Path $obj)) {
  $cand = Get-ChildItem -Path $outDir -Filter *.obj -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($cand) { $obj = $cand.FullName }
}
if (-not (Test-Path $obj)) { Write-Err "No OBJ found in $outDir"; Read-Host "Press ENTER to close"; exit 1 }

# Find texture
$texture = $null
$texNames = @("texture.png","albedo.png","diffuse.png")
foreach ($n in $texNames) {
  $p = Join-Path $outDir $n
  if (Test-Path $p) { $texture = $p; break }
}
if (-not $texture) {
  $anyTex = Get-ChildItem -Path $outDir -Include *.png,*.jpg,*.jpeg -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notmatch '^input\.(jpg|jpeg)$' } | Select-Object -First 1
  if ($anyTex) { $texture = $anyTex.FullName }
}

# Write MTL
$mtl = Join-Path $outDir "mesh.mtl"
$texNameForMtl = if ($texture) { [IO.Path]::GetFileName($texture) } else { "texture.png" }
@"
newmtl material_0
Ka 1.000 1.000 1.000
Kd 1.000 1.000 1.000
Ks 0.000 0.000 0.000
d 1.0
illum 2
map_Kd $texNameForMtl
"@ | Set-Content -Encoding ASCII $mtl

# Ensure OBJ references MTL (prepend if missing)
$lines = Get-Content $obj
if (-not ($lines -match '^mtllib\s+mesh\.mtl')) {
  @("mtllib mesh.mtl") + $lines | Set-Content -Encoding ASCII $obj
}
# If texture exists but name differs, copy it next to OBJ as referenced name
if ($texture -and -not (Test-Path (Join-Path $outDir $texNameForMtl))) {
  Copy-Item -Force $texture (Join-Path $outDir $texNameForMtl)
}
Write-OK "MTL ready: $mtl"

# ---------- [2/5] Export GLB via Python (trimesh) ----------
Write-Info "[2/5] Exporting GLB via Python (trimesh)"
$py = "C:\ai3d\TripoSR\.venv\Scripts\python.exe"
if (-not (Test-Path $py)) { Write-Err "Venv python not found: $py"; Read-Host "Press ENTER"; exit 1 }

# Verify/install packages if missing
$needInstall = $false
try { & $py -c "import trimesh, pygltflib" | Out-Null } catch { $needInstall = $true }
if ($needInstall) {
  Write-Info "Installing trimesh + pygltflib into venv..."
  & $py -m pip install --upgrade pip
  & $py -m pip install trimesh pygltflib
  & $py -c "import trimesh, pygltflib" | Out-Null
}

# Write small converter as ASCII (avoid BOM)
$conv = Join-Path $outDir "obj2glb_tmp.py"
@"
import sys, os, trimesh
if len(sys.argv)<3:
    print('Usage: python obj2glb_tmp.py <input.obj> <output.glb>'); sys.exit(1)
inp, outp = sys.argv[1], sys.argv[2]
wd = os.path.dirname(inp)
cur = os.getcwd()
try:
    os.chdir(wd)
    mesh = trimesh.load(os.path.basename(inp), force='mesh')
    glb_bytes = mesh.export(file_type='glb', include_normals=True)
    with open(outp, 'wb') as f:
        f.write(glb_bytes)
finally:
    os.chdir(cur)
print('Wrote', outp)
"@ | Set-Content -Encoding ASCII $conv

$glb = Join-Path $outDir "model_smooth.glb"
& $py $conv $obj $glb
Remove-Item -Force $conv -ErrorAction SilentlyContinue
if (Test-Path $glb) {
  Write-Host "Wrote $glb"
  Write-OK "GLB exported: $glb"
} else {
  Write-Err "GLB export failed"
  Read-Host "Press ENTER to close"
  exit 1
}

# ---------- [3/5] Prepare viewers ----------
Write-Info "[3/5] Preparing viewers"
$arDir = "D:\HackTheNorth\ar_view"
$wcDir = "D:\HackTheNorth\webcam_ar"
$fbDir = "D:\HackTheNorth\fullbody_ar"
New-Item -ItemType Directory -Force -Path $arDir, $wcDir, $fbDir | Out-Null

# Create minimal pages if missing
if (-not (Test-Path (Join-Path $arDir "index.html"))) {
@"
<!doctype html><html><head><meta charset="utf-8"/><title>AR Viewer</title>
<script type="module" src="https://unpkg.com/@google/model-viewer/dist/model-viewer.min.js"></script>
<style>html,body{height:100%;margin:0;background:#111} model-viewer{width:100%;height:100%}</style>
</head><body>
<model-viewer src="model.glb" ar ar-modes="scene-viewer webxr quick-look" camera-controls environment-image="neutral" shadow-intensity="1"></model-viewer>
</body></html>
"@ | Set-Content -Encoding UTF8 (Join-Path $arDir "index.html")
}
if (-not (Test-Path (Join-Path $wcDir "index.html"))) {
@"
<!doctype html><html><head><meta charset="utf-8"/><title>Webcam AR</title>
<style>html,body{margin:0;overflow:hidden;background:#000}</style>
<script type="module">
import * as THREE from 'https://unpkg.com/three@0.160/build/three.module.js';
import { GLTFLoader } from 'https://unpkg.com/three@0.160/examples/jsm/loaders/GLTFLoader.js';
import 'https://cdn.jsdelivr.net/npm/@mediapipe/camera_utils/camera_utils.js';
import 'https://cdn.jsdelivr.net/npm/@mediapipe/face_mesh/face_mesh.js';
const scene=new THREE.Scene(), camera=new THREE.PerspectiveCamera(60, innerWidth/innerHeight, .01, 100), renderer=new THREE.WebGLRenderer({antialias:true});
renderer.setSize(innerWidth,innerHeight); document.body.appendChild(renderer.domElement); camera.position.set(0,0,1.2);
const video=document.createElement('video'); video.autoplay=true; video.playsInline=true; video.muted=true;
const stream=await navigator.mediaDevices.getUserMedia({video:{facingMode:'user', width:960, height:540},audio:false}); video.srcObject=stream;
const tex=new THREE.VideoTexture(video); const bgS=new THREE.Scene(); const bgC=new THREE.OrthographicCamera(-1,1,1,-1,0,1);
bgS.add(new THREE.Mesh(new THREE.PlaneGeometry(2,2), new THREE.MeshBasicMaterial({map:tex})));
scene.add(new THREE.AmbientLight(0xffffff,1)); const d=new THREE.DirectionalLight(0xffffff,1); d.position.set(0,1,1); scene.add(d);
let model=null; new GLTFLoader().load('./model.glb',g=>{ model=g.scene; model.scale.setScalar(0.15); scene.add(model); });
addEventListener('resize',()=>{ camera.aspect=innerWidth/innerHeight; camera.updateProjectionMatrix(); renderer.setSize(innerWidth,innerHeight); });
const faceMesh = new FaceMesh.FaceMesh({ locateFile: f => `https://cdn.jsdelivr.net/npm/@mediapipe/face_mesh/${f}` });
faceMesh.setOptions({ maxNumFaces:1, refineLandmarks:true, minDetectionConfidence:.5, minTrackingConfidence:.5 });
let lm=null; faceMesh.onResults(r=>{ lm=(r.multiFaceLandmarks&&r.multiFaceLandmarks[0])?r.multiFaceLandmarks[0]:null; });
const mpCam=new Camera(video,{ onFrame: async()=>{ await faceMesh.send({image:video}); }, width:960, height:540 }); mpCam.start();
function update(){ if(!model||!lm) return; const nose=lm[1]; const x=(nose.x-.5)*2, y=(.5-nose.y)*2, z=-.5;
  const pos=new THREE.Vector3(x,y,z).unproject(camera); model.position.lerp(pos,.7); }
(function loop(){ requestAnimationFrame(loop); update(); renderer.autoClear=false; renderer.clear(); renderer.render(bgS,bgC); renderer.render(scene,camera); })();
</script></head><body></body></html>
"@ | Set-Content -Encoding UTF8 (Join-Path $wcDir "index.html")
}
if (-not (Test-Path (Join-Path $fbDir "index.html"))) {
@"
<!doctype html><html><head><meta charset="utf-8"/><title>Full-Body AR</title><meta name="viewport" content="width=device-width, initial-scale=1"/>
<style>html,body{margin:0;height:100%;overflow:hidden;background:#000}</style>
<script type="module">
import * as THREE from 'https://unpkg.com/three@0.160/build/three.module.js';
import { GLTFLoader } from 'https://unpkg.com/three@0.160/examples/jsm/loaders/GLTFLoader.js';
const scene=new THREE.Scene(), camera=new THREE.PerspectiveCamera(60, innerWidth/innerHeight, .01, 100), renderer=new THREE.WebGLRenderer({antialias:true});
renderer.setSize(innerWidth,innerHeight); document.body.appendChild(renderer.domElement);
const video=document.createElement('video'); video.autoplay=true; video.playsInline=true; video.muted=true;
const stream=await navigator.mediaDevices.getUserMedia({video:{facingMode:'user',width:960,height:540},audio:false}); video.srcObject=stream;
const vTex=new THREE.VideoTexture(video); const bgS=new THREE.Scene(); const bgC=new THREE.OrthographicCamera(-1,1,1,-1,0,1);
bgS.add(new THREE.Mesh(new THREE.PlaneGeometry(2,2), new THREE.MeshBasicMaterial({map:vTex})));
scene.add(new THREE.AmbientLight(0xffffff,1)); const d=new THREE.DirectionalLight(0xffffff,1); d.position.set(0,1,1); scene.add(d);
let model=null; new GLTFLoader().load('./model.glb',g=>{ model=g.scene; model.visible=false; scene.add(model); });
addEventListener('resize',()=>{ camera.aspect=innerWidth/innerHeight; camera.updateProjectionMatrix(); renderer.setSize(innerWidth,innerHeight); });
const mp='https://cdn.jsdelivr.net/npm/@mediapipe/'; await Promise.all([ import(mp+'pose/pose.js'), import(mp+'camera_utils/camera_utils.js') ]);
const pose=new Pose.Pose({ locateFile:f=>mp+'pose/'+f }); pose.setOptions({ modelComplexity:1, smoothLandmarks:true, minDetectionConfidence:.5, minTrackingConfidence:.5 });
let LMs=null; pose.onResults(r=>{ LMs=(r.poseLandmarks&&r.poseLandmarks[0])?r.poseLandmarks:null; });
const cam=new Camera(video,{ onFrame:async()=>{ await pose.send({image:video}); }, width:960, height:540 }); cam.start();
function ndcToWorld(x,y,z){ const v=new THREE.Vector3(x,y,(z-camera.near)/(camera.far-camera.near)*2-1); v.unproject(camera); return v; }
let curPos=new THREE.Vector3(0,0,-1.2), curYaw=0, curS=1; function lerp(a,b,t){ return a+(b-a)*t; }
function update(){
  if(!model||!LMs) return; const lh=LMs[23], rh=LMs[24], ls=LMs[11], rs=LMs[12]; if(!lh||!rh||!ls||!rs) return;
  const hipX=(lh.x+rh.x)/2, hipY=(lh.y+rh.y)/2; const ndcX=(hipX-.5)*2, ndcY=(.5-hipY)*2;
  const world=ndcToWorld(ndcX, ndcY, -1.2);
  const dx=(ls.x-rs.x), dy=(ls.y-rs.y); const yaw=Math.atan2(dx,dy);
  const shoulderDist=Math.hypot(dx,dy); const s=Math.min(2.0, Math.max(0.2, shoulderDist*3.0));
  const t=.4; curPos.lerp(world,1-t); curYaw=lerp(curYaw,yaw,1-t); curS=lerp(curS,s,1-t);
  model.position.copy(curPos); model.rotation.set(0,curYaw,0); model.scale.setScalar(curS); model.visible=true;
}
(function loop(){ requestAnimationFrame(loop); update(); renderer.autoClear=false; renderer.clear(); renderer.render(bgS,bgC); renderer.render(scene,camera); })();
</script></head><body></body></html>
"@ | Set-Content -Encoding UTF8 (Join-Path $fbDir "index.html")
}

# ---------- [4/5] Copy GLB ----------
Write-Info "[4/5] Copying GLB to viewers"
Copy-Item -Force $glb (Join-Path $arDir "model.glb")
Copy-Item -Force $glb (Join-Path $wcDir "model.glb")
Copy-Item -Force $glb (Join-Path $fbDir "model.glb")
Write-OK "GLB copied."

# ---------- [5/5] Start servers + show exact URLs ----------
Write-Info "[5/5] Starting servers (8000/8001/8002 on 0.0.0.0)"
function Start-Server($dir,$port){
  $listening = (Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue)
  if ($null -eq $listening) {
    Start-Process -WindowStyle Minimized -FilePath "powershell.exe" -ArgumentList `
      "-NoLogo -NoProfile -ExecutionPolicy Bypass -Command `"Set-Location `"$dir`"; python -m http.server $port --bind 0.0.0.0`""
    Start-Sleep -Seconds 1
  }
}
Start-Server $arDir 8000
Start-Server $wcDir 8001
Start-Server $fbDir 8002

# Robust Wi-Fi IPv4 detection for phone
$ipObj = Get-NetIPConfiguration |
  Where-Object { $_.IPv4DefaultGateway -ne $null -and $_.NetAdapter.Status -eq 'Up' } |
  Select-Object -First 1
$ip = $null
if ($ipObj -and $ipObj.IPv4Address) { $ip = $ipObj.IPv4Address.IPAddress }
if (-not $ip) {
  $ip = (Get-NetIPAddress |
    Where-Object { $_.AddressFamily -eq 'IPv4' -and $_.IPAddress -notlike '169.254*' -and $_.IPAddress -ne '127.0.0.1' } |
    Select-Object -First 1 -ExpandProperty IPAddress)
}
if (-not $ip) { $ip = '127.0.0.1' }

Write-Host ""
Write-OK ("Laptop links:")
Write-OK ("  Mobile AR:        http://localhost:8000/")
Write-OK ("  Webcam AR (face): http://localhost:8001/")
Write-OK ("  Full-body AR:     http://localhost:8002/")
Write-Host ""
Write-OK ("Phone (same Wi-Fi) links:")
Write-OK ("  Mobile AR:        http://$ip:8000/")
Write-OK ("  Webcam AR (face): http://$ip:8001/  (mobile browsers may block camera on HTTP)")
Write-OK ("  Full-body AR:     http://$ip:8002/  (mobile browsers may block camera on HTTP)")
Write-Host ""
Write-Warn "Tip: For phone camera on 8001/8002 use HTTPS tunnel (e.g. cloudflared):"
Write-Host "  cloudflared.exe tunnel --url http://localhost:8001" -ForegroundColor Yellow
Write-Host "  cloudflared.exe tunnel --url http://localhost:8002" -ForegroundColor Yellow

Start-Process "http://localhost:8000/"
Start-Process "http://localhost:8001/"
Start-Process "http://localhost:8002/"

Read-Host "Press ENTER to close this window"
