#!/bin/bash
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

ENOWXAI_DIR="$HOME/.enowxai"
TUNNEL_SCRIPT="/usr/local/bin/enowxai-tunnel.sh"

log() { echo -e "  ${GREEN}●${NC} $1"; }
warn() { echo -e "  ${YELLOW}●${NC} $1"; }
die() { echo -e "  ${RED}●${NC} $1"; exit 1; }
info() { echo -e "  ${DIM}$1${NC}"; }
header() {
    echo ""
    echo -e "  ${BOLD}$1${NC}"
    echo -e "  ${DIM}$(printf '%.0s─' $(seq 1 50))${NC}"
}

echo ""
echo -e "  ${CYAN}${BOLD}EnowX AI${NC} ${DIM}— Auto Installer${NC}"
echo -e "  ${DIM}$(printf '%.0s━' $(seq 1 50))${NC}"

if [[ -f /etc/os-release ]]; then . /etc/os-release; OS=$ID
elif [[ "$(uname)" == "Darwin" ]]; then OS="macos"
elif [[ -d /data/data/com.termux ]]; then OS="termux"
else OS="unknown"; fi

ARCH=$(uname -m)
case $ARCH in x86_64|amd64) ARCH="amd64";; aarch64|arm64) ARCH="arm64";; esac
info "$OS $ARCH"

header "Dependencies"

case $OS in
    ubuntu|debian|pop|kali)
        sudo apt-get update -qq && sudo apt-get upgrade -y -qq
        sudo apt-get install -y --no-install-recommends \
            curl wget ca-certificates python3 python3-venv \
            xvfb fonts-liberation libnss3 libatk-bridge2.0-0 libdrm2 \
            libxcomposite1 libxdamage1 libxrandr2 libgbm1 libasound2 \
            libpango-1.0-0 libcairo2 libcups2 libxss1 libgtk-3-0 \
            libdbus-glib-1-2 2>/dev/null || true
        sudo apt-get install -y libasound2t64 2>/dev/null || true
        ;;
    arch|manjaro)
        sudo pacman -Syu --noconfirm
        sudo pacman -S --noconfirm --needed curl wget python xorg-server-xvfb \
            gtk3 nss alsa-lib libdrm pango cairo libcups dbus-glib ttf-liberation 2>/dev/null || true
        ;;
    fedora|rhel|centos)
        sudo dnf update -y -q
        sudo dnf install -y -q curl wget python3 xorg-x11-server-Xvfb gtk3 nss \
            alsa-lib libdrm pango cairo cups-libs dbus-glib liberation-fonts 2>/dev/null || true
        ;;
    macos) command -v brew &>/dev/null && brew install python3 curl 2>/dev/null || true ;;
    termux) pkg update -y && pkg install -y curl wget python 2>/dev/null || true ;;
esac
log "System packages installed"

header "EnowX AI"

if command -v enowxai &>/dev/null; then
    log "Already installed ($(enowxai version 2>/dev/null))"
    enowxai update 2>/dev/null || true
else
    curl -sSL https://api.enowxlabs.com/install/enowx-ai | bash
    export PATH="$HOME/.local/bin:$PATH"
fi
command -v enowxai &>/dev/null || die "Install failed"
log "Binary ready"

header "Service"

enowxai setup 2>/dev/null || warn "Auth setup skipped"
enowxai stop 2>/dev/null || true
enowxai start --host 0.0.0.0
sleep 2
enowxai autostart 2>/dev/null || true
log "Proxy running on :1430"
log "Dashboard running on :1431"

header "Cloudflared"

if ! command -v cloudflared &>/dev/null; then
    case $OS in
        ubuntu|debian|pop|kali)
            sudo mkdir -p /usr/share/keyrings
            curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
            echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/cloudflared.list >/dev/null
            sudo apt-get update -qq && sudo apt-get install -y cloudflared
            ;;
        *)
            curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}" -o /usr/local/bin/cloudflared
            sudo chmod +x /usr/local/bin/cloudflared
            ;;
    esac
fi
command -v cloudflared &>/dev/null && log "Installed" || die "Failed"

header "Tunnel"

mkdir -p "$ENOWXAI_DIR"

sudo tee "$TUNNEL_SCRIPT" >/dev/null <<'EOF'
#!/bin/bash
ENOWXAI_DIR="$HOME/.enowxai"
mkdir -p "$ENOWXAI_DIR"

start_tunnel() {
    local port=$1
    local label=$2
    local logfile="/var/log/enowxai-tunnel-${label}.log"
    local urlfile="$ENOWXAI_DIR/${label}_url.txt"

    cloudflared tunnel --url "http://localhost:${port}" --no-autoupdate >> "$logfile" 2>&1 &
    local pid=$!

    for i in $(seq 1 30); do
        sleep 2
        local url=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' "$logfile" 2>/dev/null | tail -1)
        if [[ -n "$url" ]]; then
            echo "$url" > "$urlfile"
            echo "[$(date)] ${label}: $url" >> "$ENOWXAI_DIR/tunnel_urls.txt"
            break
        fi
    done
    echo $pid
}

while true; do
    pkill -f "cloudflared tunnel --url" 2>/dev/null || true
    sleep 1

    > /var/log/enowxai-tunnel-api.log
    > /var/log/enowxai-tunnel-dash.log

    API_PID=$(start_tunnel 1430 api)
    DASH_PID=$(start_tunnel 1431 dash)

    while kill -0 $API_PID 2>/dev/null && kill -0 $DASH_PID 2>/dev/null; do
        sleep 10
    done

    pkill -f "cloudflared tunnel --url" 2>/dev/null || true
    sleep 5
done
EOF
sudo chmod +x "$TUNNEL_SCRIPT"
log "Tunnel script created"

if command -v systemctl &>/dev/null; then
    sudo tee /etc/systemd/system/enowxai-tunnel.service >/dev/null <<EOF
[Unit]
Description=EnowX AI Tunnel
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$TUNNEL_SCRIPT
Restart=always
RestartSec=5
Environment=HOME=$HOME

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable --now enowxai-tunnel
else
    nohup "$TUNNEL_SCRIPT" &>/dev/null &
fi
log "Service enabled (auto-restart)"

info "Waiting for URLs..."
for i in $(seq 1 30); do
    [[ -f "$ENOWXAI_DIR/api_url.txt" && -f "$ENOWXAI_DIR/dash_url.txt" ]] && break
    sleep 2
done

API_URL=$(cat "$ENOWXAI_DIR/api_url.txt" 2>/dev/null || echo "loading...")
DASH_URL=$(cat "$ENOWXAI_DIR/dash_url.txt" 2>/dev/null || echo "loading...")
APIKEY=$(enowxai apikey 2>/dev/null || echo "set di dashboard")

echo ""
echo -e "  ${BOLD}${GREEN}Done${NC}"
echo -e "  ${DIM}$(printf '%.0s━' $(seq 1 50))${NC}"
echo ""
echo -e "  ${BOLD}Dashboard${NC}  ${CYAN}$DASH_URL${NC}"
echo -e "  ${BOLD}API${NC}        ${CYAN}$API_URL/v1${NC}"
echo -e "  ${BOLD}Key${NC}        ${YELLOW}$APIKEY${NC}"
echo ""
echo -e "  ${DIM}Next: buka dashboard → set password → add license → add accounts${NC}"
echo ""
echo -e "  ${DIM}cat ~/.enowxai/api_url.txt${NC}          ${DIM}cek URL API${NC}"
echo -e "  ${DIM}cat ~/.enowxai/dash_url.txt${NC}         ${DIM}cek URL dashboard${NC}"
echo -e "  ${DIM}sudo systemctl restart enowxai-tunnel${NC}  ${DIM}restart tunnel${NC}"
echo ""
