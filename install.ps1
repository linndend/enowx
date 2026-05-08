# EnowX AI - Auto Installer for Windows (Local)
# Usage: irm https://raw.githubusercontent.com/linndend/enowx/main/install.ps1 | iex

$ErrorActionPreference = "Stop"

function Write-Log { param($msg) Write-Host "  $([char]0x25CF) $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "  $([char]0x25CF) $msg" -ForegroundColor Yellow }
function Write-Err { param($msg) Write-Host "  $([char]0x25CF) $msg" -ForegroundColor Red; exit 1 }
function Write-Info { param($msg) Write-Host "  $msg" -ForegroundColor DarkGray }
function Write-Header { param($msg)
    Write-Host ""
    Write-Host "  $msg" -ForegroundColor White
    Write-Host "  $('─' * 50)" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "  EnowX AI" -ForegroundColor Cyan -NoNewline
Write-Host " — Installer (Windows)" -ForegroundColor DarkGray
Write-Host "  $('━' * 50)" -ForegroundColor DarkGray

Write-Header "1/3 Install EnowX AI"

$enowxai = "$env:USERPROFILE\.local\bin\enowxai.exe"
if (Test-Path $enowxai) {
    Write-Log "Sudah terinstall"
    & $enowxai update 2>$null
} else {
    Write-Info "Downloading..."
    irm "https://api.enowxlabs.com/install/enowx-ai?platform=windows" | iex
}

$envPath = "$env:USERPROFILE\.local\bin"
if ($env:PATH -notlike "*$envPath*") {
    $env:PATH = "$envPath;$env:PATH"
}

if (!(Get-Command enowxai -ErrorAction SilentlyContinue)) {
    Write-Err "Install gagal"
}
Write-Log "EnowX AI ready"

Write-Header "2/3 Setup & Start"

try { enowxai setup 2>$null } catch { Write-Warn "Auth setup skip" }
try { enowxai stop 2>$null } catch {}
enowxai start
Start-Sleep -Seconds 2
try { enowxai autostart 2>$null } catch {}
Write-Log "Proxy running on localhost:1430"
Write-Log "Dashboard running on localhost:1431"

Write-Header "3/3 MITM Proxy (Antigravity/Cursor/Trae)"

Write-Info "Enabling MITM proxy..."
try {
    enowxai mitm enable
    Write-Log "MITM enabled"
} catch {
    Write-Warn "MITM setup gagal. Jalankan manual: enowxai mitm enable"
}

$apiKey = try { (enowxai apikey 2>$null) } catch { "jalankan: enowxai apikey" }

Write-Host ""
Write-Host "  $('═' * 50)" -ForegroundColor Green
Write-Host "  EnowX AI - Ready!" -ForegroundColor White
Write-Host "  $('═' * 50)" -ForegroundColor Green
Write-Host ""
Write-Host "  Dashboard : " -NoNewline; Write-Host "http://localhost:1431" -ForegroundColor Cyan
Write-Host "  API       : " -NoNewline; Write-Host "http://localhost:1430/v1" -ForegroundColor Cyan
Write-Host "  API Key   : " -NoNewline; Write-Host "$apiKey" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Setup:" -ForegroundColor White
Write-Host "   1. Buka http://localhost:1431" -ForegroundColor DarkGray
Write-Host "   2. Set password admin" -ForegroundColor DarkGray
Write-Host "   3. Add license key" -ForegroundColor DarkGray
Write-Host "   4. Add accounts" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Antigravity/Cursor/Trae otomatis ke-intercept via MITM." -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Commands:" -ForegroundColor White
Write-Host "   enowxai status        # cek status" -ForegroundColor DarkGray
Write-Host "   enowxai mitm status   # cek MITM" -ForegroundColor DarkGray
Write-Host "   enowxai models        # list model" -ForegroundColor DarkGray
Write-Host "   enowxai stop          # stop proxy" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  $('═' * 50)" -ForegroundColor Green
Write-Host ""
