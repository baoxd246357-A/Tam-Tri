<#
 Cai MCP AutoCAD (nhanh gpt2nndk/autocad-mcp-nndk) cho Claude Desktop tren Windows.
 Dung:  install.bat            (hoac)  powershell -File install.ps1
 Tuy chon:
   -InstallDir  C:\tools\autocad-mcp-nndk   thu muc dat ma nguon
   -IpcDir      C:/temp                      thu muc trao doi voi AutoCAD
   -Backend     auto | file_ipc | ezdxf      mac dinh auto
   -Timeout     30                           giay, 1..300
 Script KHONG can khoa API. MCP chay tren may ban, noi chuyen voi AutoCAD qua file trong IpcDir.
#>
param(
  [string]$InstallDir = (Join-Path $env:USERPROFILE 'autocad-mcp-nndk'),
  [string]$IpcDir     = 'C:/temp',
  [ValidateSet('auto','file_ipc','ezdxf')][string]$Backend = 'auto',
  [ValidateRange(1,300)][int]$Timeout = 30,
  [string]$RepoUrl    = 'https://github.com/gpt2nndk/autocad-mcp-nndk.git'
)
$ErrorActionPreference = 'Stop'
function Step($m){ Write-Host "`n== $m" -ForegroundColor Cyan }
function Ok($m){ Write-Host "[OK]  $m" -ForegroundColor Green }
function Warn($m){ Write-Host "[!]   $m" -ForegroundColor Yellow }
function Die($m){ Write-Host "[LOI] $m" -ForegroundColor Red; exit 1 }
function Has($c){ [bool](Get-Command $c -ErrorAction SilentlyContinue) }

Step '1/7 Kiem tra yeu cau'
if ($PSVersionTable.Platform -and $PSVersionTable.Platform -ne 'Win32NT') { Die 'Phai chay tren Windows (khong phai WSL).' }
if (-not (Has git)) { Die 'Chua co git. Cai: winget install Git.Git roi chay lai.' }
Ok 'git'
if (-not (Has uv)) {
  Warn 'Chua co uv.'
  if (Has winget) {
    $a = Read-Host 'Cai uv bang winget? (y/n)'
    if ($a -eq 'y') {
      winget install --id astral-sh.uv -e --accept-source-agreements --accept-package-agreements
      $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
    }
  }
  if (-not (Has uv)) { Die 'Can uv. Xem https://docs.astral.sh/uv/getting-started/installation/ roi mo cua so moi va chay lai.' }
}
Ok ('uv ' + (uv --version))
# uv sync tu tai Python phu hop neu thieu; chi bao neu Python he thong cu.
if (Has python) {
  $v = & python -c "import sys;print('%d.%d'%sys.version_info[:2])" 2>$null
  if ($v) { if ([version]$v -lt [version]'3.10') { Warn "Python he thong $v < 3.10 (uv se dung ban rieng neu can)." } else { Ok "python $v" } }
}

Step '2/7 Tai ma nguon'
if (Test-Path (Join-Path $InstallDir '.git')) {
  Warn "Da co $InstallDir - cap nhat (git pull)."
  git -C $InstallDir pull --ff-only
} else {
  git clone $RepoUrl $InstallDir
}
if ($LASTEXITCODE -ne 0) { Die 'git that bai (kiem tra mang/duong dan).' }
Ok $InstallDir

Step '3/7 Cai thu vien (uv sync)'
Push-Location $InstallDir
try { uv sync; if ($LASTEXITCODE -ne 0) { Die 'uv sync that bai.' } } finally { Pop-Location }
$py = Join-Path $InstallDir '.venv\Scripts\python.exe'
if (-not (Test-Path $py)) { Die "Khong thay $py" }
& $py -c "import autocad_mcp" 2>$null
if ($LASTEXITCODE -ne 0) { Die 'Khong import duoc autocad_mcp trong .venv.' }
Ok 'import autocad_mcp'

Step '4/7 Thu muc trao doi IPC'
$ipcWin = $IpcDir -replace '/','\'
New-Item -ItemType Directory -Force -Path $ipcWin | Out-Null
$t = Join-Path $ipcWin '.mcp_write_test'
try { Set-Content $t 'x'; Remove-Item $t; Ok "$ipcWin ghi duoc" } catch { Die "Khong ghi duoc vao $ipcWin" }

Step '5/7 File LISP'
$lsp = Join-Path $InstallDir 'lisp-code\mcp_dispatch.lsp'
if (-not (Test-Path $lsp)) { Die "Khong thay $lsp" }
$ipcLine = Select-String -Path $lsp -Pattern '\*mcp-ipc-dir\*' | Select-Object -First 1
if ($ipcLine) { Write-Host "  $($ipcLine.Line.Trim())" }
if ($IpcDir -ne 'C:/temp') { Warn "Ban doi IpcDir: phai sua *mcp-ipc-dir* trong mcp_dispatch.lsp thanh \"$IpcDir/\" cho khop." }
$hits = Select-String -Path $lsp -Pattern 'vl-cmdf|command|startapp|shell|DeleteFile|vl-file-delete' -SimpleMatch:$false | Measure-Object
Write-Host "  Goi y: doc file nay truoc khi nap (co $($hits.Count) dong goi lenh/xoa file). Tool execute_lisp chay AutoLISP tuy y."
Set-Clipboard -Value $lsp -ErrorAction SilentlyContinue

Step '6/7 Ghi claude_desktop_config.json'
$cfgDir = Join-Path $env:APPDATA 'Claude'
$cfg = Join-Path $cfgDir 'claude_desktop_config.json'
New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null
$obj = [pscustomobject]@{}
if (Test-Path $cfg) {
  Copy-Item $cfg "$cfg.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
  $raw = Get-Content $cfg -Raw
  if ($raw.Trim()) { try { $obj = $raw | ConvertFrom-Json } catch { Die "Config hien tai khong phai JSON hop le: $cfg (da sao luu .bak). Sua tay roi chay lai." } }
}
if (-not $obj.PSObject.Properties['mcpServers']) { $obj | Add-Member -NotePropertyName mcpServers -NotePropertyValue ([pscustomobject]@{}) }
$server = [pscustomobject]@{
  command = $py
  args    = @('-m','autocad_mcp')
  env     = [pscustomobject]@{
    AUTOCAD_MCP_BACKEND     = $Backend
    AUTOCAD_MCP_IPC_TIMEOUT = "$Timeout"
  }
}
if ($IpcDir -ne 'C:/temp') { $server.env | Add-Member -NotePropertyName AUTOCAD_MCP_IPC_DIR -NotePropertyValue $IpcDir }
$obj.mcpServers | Add-Member -NotePropertyName 'autocad-mcp' -NotePropertyValue $server -Force
$json = $obj | ConvertTo-Json -Depth 10
[IO.File]::WriteAllText($cfg, $json, (New-Object Text.UTF8Encoding($false)))   # UTF-8 khong BOM
Ok $cfg
if (-not (Test-Path (Join-Path $env:APPDATA 'Claude\logs')) -and (Get-ChildItem "$env:LOCALAPPDATA\Packages" -Filter 'Claude_*' -ErrorAction SilentlyContinue)) {
  Warn 'Co ve la ban Claude cai tu Microsoft Store: file config co the nam o %LOCALAPPDATA%\Packages\Claude_*\LocalCache\Roaming\Claude. Neu Claude khong thay MCP, chep file tren sang do.'
}

Step '7/7 Kiem tra khoi dong server'
$init = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"selftest","version":"0"}}}'
$env:AUTOCAD_MCP_BACKEND = $Backend
$out = $init | & $py -m autocad_mcp 2>&1 | Select-Object -First 5
if ($out -match 'serverInfo|protocolVersion') { Ok 'Server tra loi initialize' } else { Warn "Khong thay phan hoi initialize (co the van binh thuong). Dau ra:`n$out" }

Write-Host @"

================ BUOC TIEP THEO (lam tay) ================
1. Mo AutoCAD, go APPLOAD, chon:
     $lsp
   Bam Load, phai thay: === MCP Dispatch v3.1 loaded ===
   (Tuy chon: Contents -> Startup Suite de tu nap moi lan.)
2. Thoat han Claude Desktop (khay he thong -> Quit) roi mo lai.
3. Mo AutoCAD voi ban ve nhap, hoi Claude: "goi system status"
     backend: file_ipc  = dang dieu khien AutoCAD that
     backend: ezdxf     = chua nap mcp_dispatch.lsp (lam lai buoc 1)
4. Thu: drawing info -> entity count -> view get_screenshot.
Khoa API: KHONG can. Neu ban gap loi 'API key', do la cua Claude/ung dung khac, khong phai cua MCP nay.
==========================================================
"@
