# EnowX AI - Auto Installer for Windows
# Usage: irm https://raw.githubusercontent.com/linndend/enowx/main/install.ps1 | iex

$ErrorActionPreference = "Stop"

function Write-Log { param($msg) Write-Host "  $([char]0x25CF) $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "  $([char]0x25CF) $msg" -ForegroundColor Yellow }
function Write-Err { param($msg) Write-Host "  $([char]0x25CF) $msg" -ForegroundColor Red; exit 1 }
function Write-Info { param($msg) Write-Host "  $msg" -ForegroundColor DarkGray }
function Write-Header { param($msg)
    Write-Host ""
    Write-Host "  $msg" -ForegroundColor White -NoNewline
    Write-Host ""
    Write-Host "  $('─' * 50)" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "  EnowX AI" -ForegroundColor Cyan -NoNewline
Write-Host " — Auto Installer (Windows)" -ForegroundColor DarkGray
Write-Host "  $('━' * 50)" -ForegroundColor DarkGray

Write-Header "1/5 Install EnowX AI"

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

Write-Header "2/5 Setup & Start"

try { enowxai setup 2>$null } catch { Write-Warn "Auth setup skip" }
try { enowxai stop 2>$null } catch {}
enowxai start --host 0.0.0.0
Start-Sleep -Seconds 2
try { enowxai autostart 2>$null } catch {}
Write-Log "Proxy running on :1430"
Write-Log "Dashboard running on :1431"

Write-Header "3/5 Install Cloudflared"

if (!(Get-Command cloudflared -ErrorAction SilentlyContinue)) {
    Write-Info "Downloading cloudflared..."
    $arch = if ([Environment]::Is64BitOperatingSystem) { "amd64" } else { "386" }
    $cfUrl = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-$arch.exe"
    $cfPath = "$env:USERPROFILE\.local\bin\cloudflared.exe"
    Invoke-WebRequest -Uri $cfUrl -OutFile $cfPath -UseBasicParsing
    if (Test-Path $cfPath) {
        Write-Log "cloudflared installed"
    } else {
        Write-Err "cloudflared gagal download"
    }
} else {
    Write-Log "cloudflared sudah ada"
}

Write-Header "4/5 Setup Tunnel"

$enowxDir = "$env:USERPROFILE\.enowxai"
if (!(Test-Path $enowxDir)) { New-Item -ItemType Directory -Path $enowxDir -Force | Out-Null }

$tunnelScript = @'
$enowxDir = "$env:USERPROFILE\.enowxai"
if (!(Test-Path $enowxDir)) { New-Item -ItemType Directory -Path $enowxDir -Force | Out-Null }

while ($true) {
    Get-Process cloudflared -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1

    $apiJob = Start-Job -ScriptBlock {
        $output = & cloudflared tunnel --url http://localhost:1430 --no-autoupdate 2>&1
        $output | ForEach-Object {
            if ($_ -match 'https://[a-z0-9-]+\.trycloudflare\.com') {
                $matches[0] | Out-File "$env:USERPROFILE\.enowxai\api_url.txt" -Force
                Add-Content "$env:USERPROFILE\.enowxai\tunnel_urls.txt" "[$(Get-Date)] API: $($matches[0])"
            }
        }
    }
    Start-Sleep -Seconds 4

    $dashJob = Start-Job -ScriptBlock {
        $output = & cloudflared tunnel --url http://localhost:1431 --no-autoupdate 2>&1
        $output | ForEach-Object {
            if ($_ -match 'https://[a-z0-9-]+\.trycloudflare\.com') {
                $matches[0] | Out-File "$env:USERPROFILE\.enowxai\dash_url.txt" -Force
                Add-Content "$env:USERPROFILE\.enowxai\tunnel_urls.txt" "[$(Get-Date)] Dash: $($matches[0])"
            }
        }
    }

    Wait-Job $apiJob, $dashJob -Any | Out-Null
    Remove-Job $apiJob, $dashJob -Force -ErrorAction SilentlyContinue
    Get-Process cloudflared -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5
}
'@

$scriptPath = "$enowxDir\tunnel.ps1"
$tunnelScript | Out-File -FilePath $scriptPath -Encoding UTF8 -Force
Write-Log "Tunnel script created"

Write-Header "5/5 Start Tunnel"

Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`"" -WindowStyle Hidden

$taskName = "EnowXAI-Tunnel"
$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if (!$existingTask) {
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`""
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $settings = New-ScheduledTaskSettingsSet -RestartInterval (New-TimeSpan -Seconds 10) -RestartCount 999 -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -RunLevel Highest -Force | Out-Null
    Write-Log "Scheduled task created (auto-start on boot)"
} else {
    Write-Log "Scheduled task already exists"
}

Write-Info "Waiting for tunnel URLs..."
for ($i = 0; $i -lt 20; $i++) {
    if ((Test-Path "$enowxDir\api_url.txt") -and (Test-Path "$enowxDir\dash_url.txt")) { break }
    Start-Sleep -Seconds 2
}

$apiUrl = if (Test-Path "$enowxDir\api_url.txt") { Get-Content "$enowxDir\api_url.txt" } else { "loading..." }
$dashUrl = if (Test-Path "$enowxDir\dash_url.txt") { Get-Content "$enowxDir\dash_url.txt" } else { "loading..." }
$apiKey = try { (enowxai apikey 2>$null) } catch { "set di dashboard" }

Write-Host ""
Write-Host "  $('═' * 50)" -ForegroundColor Green
Write-Host "  EnowX AI - Ready!" -ForegroundColor White
Write-Host "  $('═' * 50)" -ForegroundColor Green
Write-Host ""
Write-Host "  Dashboard : " -NoNewline; Write-Host "$dashUrl" -ForegroundColor Cyan
Write-Host "  API       : " -NoNewline; Write-Host "$apiUrl/v1" -ForegroundColor Cyan
Write-Host "  API Key   : " -NoNewline; Write-Host "$apiKey" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Setup:" -ForegroundColor White
Write-Host "   1. Buka dashboard -> set password" -ForegroundColor DarkGray
Write-Host "   2. Add license key dari dashboard" -ForegroundColor DarkGray
Write-Host "   3. Add accounts dari dashboard" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Cek URL:" -ForegroundColor White
Write-Host "   cat ~\.enowxai\api_url.txt" -ForegroundColor DarkGray
Write-Host "   cat ~\.enowxai\dash_url.txt" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  MITM (Antigravity/Cursor):" -ForegroundColor White
Write-Host "   enowxai mitm enable" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  $('═' * 50)" -ForegroundColor Green
Write-Host ""
