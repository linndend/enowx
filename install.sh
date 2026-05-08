#!/bin/bash
#
# EnowX AI - One-Line Installer
# Usage: wget -qO- https://raw.githubusercontent.com/enowX-Labs/enowx-ai/main/install.sh | bash
#

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

ENOWXAI_DIR="$HOME/.enowxai"
TUNNEL_SCRIPT="/usr/local/bin/enowxai-tunnel.sh"

log() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
die() { echo -e "${RED}[✗]${NC} $1"; exit 1; }
info() { echo -e "${CYAN}[i]${NC} $1"; }
step() { echo -e "\n${BOLD}━━━ $1 ━━━${NC}\n"; }

echo -e "${CYAN}${BOLD}"
echo " ╔═════════════════════════════════════════════╗"
echo " ║  EnowX AI - Auto Installer + CF Tunnel     ║"
echo " ╚═════════════════════════════════════════════╝"
echo -e "${NC}"

# Detect OS & arch
if [[ -f /etc/os-release ]]; then . /etc/os-release; OS=$ID
elif [[ "$(uname)" == "Darwin" ]]; then OS="macos"
elif [[ -d /data/data/com.termux ]]; then OS="termux"
else OS="unknown"; fi

ARCH=$(uname -m)
case $ARCH in x86_64|amd64) ARCH="amd64";; aarch64|arm64) ARCH="arm64";; esac

info "OS: $OS | Arch: $ARCH"

# ═══ 1. Dependencies ═══
step "1/6 Dependencies"
case $OS in
    ubuntu|debian|pop|kali)
        sudo apt-get update -qq && sudo apt-get upgrade -y
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
        sudo dnf update -y
        sudo dnf install -y curl wget python3 xorg-x11-server-Xvfb gtk3 nss \
            alsa-lib libdrm pango cairo cups-libs dbus-glib liberation-fonts 2>/dev/null || true
        ;;
    macos) command -v brew &>/dev/null && brew install python3 curl 2>/dev/null || true ;;
    termux) pkg update -y && pkg install -y curl wget python 2>/dev/null || true ;;
esac
log "Done"

# ═══ 2. Install EnowX AI ═══
step "2/6 Install EnowX AI"
if command -v enowxai &>/dev/null; then
    log "Already installed: $(enowxai version 2>/dev/null)"
    enowxai update 2>/dev/null || true
else
    curl -sSL https://api.enowxlabs.com/install/enowx-ai | bash
    export PATH="$HOME/.local/bin:$PATH"
fi
command -v enowxai &>/dev/null || die "Install failed"
log "EnowX AI OK"

# ═══ 3. Start EnowX AI ═══
step "3/6 Start EnowX AI"
enowxai setup 2>/dev/null || warn "Auth setup skip"
enowxai stop 2>/dev/null || true
enowxai start --host 0.0.0.0
sleep 2
enowxai autostart 2>/dev/null || true
log "Running on port 1430 (API) & 1431 (Dashboard)"

# ═══ 4. Install cloudflared ═══
step "4/6 Install Cloudflared"
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
command -v cloudflared &>/dev/null && log "cloudflared OK" || die "cloudflared failed"

# ═══ 5. Tunnel Script (auto-restart, capture URL) ═══
step "5/6 Setup Tunnel"
mkdir -p "$ENOWXAI_DIR"

sudo tee "$TUNNEL_SCRIPT" >/dev/null <<'EOF'
#!/bin/bash
ENOWXAI_DIR="$HOME/.enowxai"
mkdir -p "$ENOWXAI_DIR"

while true; do
    # Kill old tunnels
    pkill -f "cloudflared tunnel --url http://localhost:143" 2>/dev/null || true
    sleep 1

    # API tunnel (1430)
    cloudflared tunnel --url http://localhost:1430 --no-autoupdate 2>&1 | \
        tee -a /var/log/enowxai-tunnel-api.log | \
        grep --line-buffered -o 'https://[a-z0-9-]*\.trycloudflare\.com' | \
        head -1 | while read url; do
            echo "$url" > "$ENOWXAI_DIR/api_url.txt"
            echo "[$(date)] API: $url" >> "$ENOWXAI_DIR/tunnel_urls.txt"
        done &
    sleep 4

    # Dashboard tunnel (1431)
    cloudflared tunnel --url http://localhost:1431 --no-autoupdate 2>&1 | \
        tee -a /var/log/enowxai-tunnel-dash.log | \
        grep --line-buffered -o 'https://[a-z0-9-]*\.trycloudflare\.com' | \
        head -1 | while read url; do
            echo "$url" > "$ENOWXAI_DIR/dash_url.txt"
            echo "[$(date)] Dash: $url" >> "$ENOWXAI_DIR/tunnel_urls.txt"
        done &

    # Wait, if any tunnel dies restart all
    wait -n 2>/dev/null
    echo "[$(date)] Tunnel died, restarting..." >> /var/log/enowxai-tunnel-api.log
    pkill -f "cloudflared tunnel --url http://localhost:143" 2>/dev/null || true
    sleep 5
done
EOF
sudo chmod +x "$TUNNEL_SCRIPT"
log "Tunnel script ready"

# ═══ 6. Systemd + Start ═══
step "6/6 Start Tunnel (systemd auto-restart)"
if command -v systemctl &>/dev/null; then
    sudo tee /etc/systemd/system/enowxai-tunnel.service >/dev/null <<EOF
[Unit]
Description=EnowX AI CF Quick Tunnel
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

# Wait for URLs
info "Waiting for tunnel URLs..."
for i in $(seq 1 20); do
    [[ -f "$ENOWXAI_DIR/api_url.txt" && -f "$ENOWXAI_DIR/dash_url.txt" ]] && break
    sleep 2
done

API_URL=$(cat "$ENOWXAI_DIR/api_url.txt" 2>/dev/null || echo "loading...")
DASH_URL=$(cat "$ENOWXAI_DIR/dash_url.txt" 2>/dev/null || echo "loading...")
APIKEY=$(enowxai apikey 2>/dev/null || echo "set di dashboard")

echo ""
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
echo -e "${BOLD} EnowX AI - Ready!${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
echo ""
echo -e " Dashboard : ${CYAN}$DASH_URL${NC}"
echo -e " API       : ${CYAN}$API_URL/v1${NC}"
echo -e " API Key   : ${YELLOW}$APIKEY${NC}"
echo ""
echo -e " ${BOLD}Setup:${NC}"
echo -e "  1. Buka dashboard → set password"
echo -e "  2. Add license key dari dashboard"
echo -e "  3. Add accounts dari dashboard"
echo ""
echo -e " ${BOLD}Cek URL (berubah tiap restart):${NC}"
echo -e "  cat ~/.enowxai/api_url.txt"
echo -e "  cat ~/.enowxai/dash_url.txt"
echo ""
echo -e " ${BOLD}Service:${NC}"
echo -e "  sudo systemctl status enowxai-tunnel"
echo -e "  sudo systemctl restart enowxai-tunnel"
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
