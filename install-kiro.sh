#!/bin/bash
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

KIRO_DIR="$HOME/.kiro-gateway"
TUNNEL_SCRIPT="/usr/local/bin/kiro-gateway-tunnel.sh"

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
echo -e "  ${CYAN}${BOLD}Kiro Gateway${NC} ${DIM}— Auto Installer${NC}"
echo -e "  ${DIM}$(printf '%.0s━' $(seq 1 50))${NC}"
echo -e "  ${DIM}Multi-account proxy for Kiro API (Claude models)${NC}"
echo ""

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
        sudo apt-get update -qq
        sudo apt-get install -y --no-install-recommends \
            curl wget ca-certificates python3 python3-pip python3-venv git 2>/dev/null || true
        ;;
    arch|manjaro)
        sudo pacman -Syu --noconfirm
        sudo pacman -S --noconfirm --needed curl wget python python-pip git 2>/dev/null || true
        ;;
    fedora|rhel|centos)
        sudo dnf install -y -q curl wget python3 python3-pip git 2>/dev/null || true
        ;;
    macos)
        command -v brew &>/dev/null && brew install python3 curl git 2>/dev/null || true
        ;;
    termux)
        pkg update -y && pkg install -y curl wget python git 2>/dev/null || true
        ;;
esac
log "System packages installed"

# ─── Clone/Update Kiro Gateway ───
header "Kiro Gateway"

mkdir -p "$KIRO_DIR"

if [[ -d "$KIRO_DIR/repo/.git" ]]; then
    log "Updating existing installation..."
    cd "$KIRO_DIR/repo" && git pull --ff-only 2>/dev/null || true
else
    log "Cloning kiro-gateway..."
    rm -rf "$KIRO_DIR/repo"
    git clone https://github.com/jwadow/kiro-gateway.git "$KIRO_DIR/repo"
fi
cd "$KIRO_DIR/repo"
log "Source ready"

# ─── Python venv ───
header "Python Environment"

if [[ ! -d "$KIRO_DIR/venv" ]]; then
    python3 -m venv "$KIRO_DIR/venv"
fi
source "$KIRO_DIR/venv/bin/activate"
pip install -q --upgrade pip
pip install -q -r requirements.txt
log "Dependencies installed"

# ─── Configuration ───
header "Configuration"

# Generate random API key if not exists
if [[ ! -f "$KIRO_DIR/repo/.env" ]]; then
    PROXY_KEY=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")
    cat > "$KIRO_DIR/repo/.env" <<EOF
PROXY_API_KEY="${PROXY_KEY}"
KIRO_REGION="us-east-1"
SERVER_HOST="0.0.0.0"
SERVER_PORT="8001"
LOG_LEVEL="INFO"
EOF
    log "Generated .env with random API key"
else
    PROXY_KEY=$(grep PROXY_API_KEY "$KIRO_DIR/repo/.env" | cut -d'"' -f2)
    log ".env already exists"
fi

# credentials.json
if [[ ! -f "$KIRO_DIR/repo/credentials.json" ]]; then
    echo "[]" > "$KIRO_DIR/repo/credentials.json"
    warn "credentials.json is empty - add accounts later"
else
    ACCOUNT_COUNT=$(python3 -c "import json; print(len(json.load(open('$KIRO_DIR/repo/credentials.json'))))" 2>/dev/null || echo "0")
    log "credentials.json: ${ACCOUNT_COUNT} accounts"
fi

# ─── Systemd Service ───
header "Service"

if command -v systemctl &>/dev/null; then
    sudo tee /etc/systemd/system/kiro-gateway.service >/dev/null <<EOF
[Unit]
Description=Kiro Gateway - Multi-account proxy for Kiro API
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$KIRO_DIR/repo
ExecStart=$KIRO_DIR/venv/bin/python main.py
Restart=always
RestartSec=5
Environment=PATH=$KIRO_DIR/venv/bin:/usr/local/bin:/usr/bin:/bin

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable kiro-gateway
    sudo systemctl restart kiro-gateway
    log "Systemd service enabled & started"
else
    # Fallback: run in background
    nohup "$KIRO_DIR/venv/bin/python" "$KIRO_DIR/repo/main.py" > "$KIRO_DIR/gateway.log" 2>&1 &
    echo $! > "$KIRO_DIR/gateway.pid"
    log "Running in background (PID: $(cat $KIRO_DIR/gateway.pid))"
fi

sleep 2

# Check if running
if curl -s http://localhost:8001/health >/dev/null 2>&1; then
    log "Gateway is running on port 8001"
else
    warn "Gateway may still be starting..."
fi

# ─── Cloudflared Tunnel ───
header "Cloudflared"

if ! command -v cloudflared &>/dev/null; then
    case $OS in
        ubuntu|debian|pop|kali)
            sudo mkdir -p /usr/share/keyrings
            curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
            echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/cloudflared.list >/dev/null
            sudo apt-get update -qq && sudo apt-get install -y cloudflared 2>/dev/null || {
                curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}" -o /usr/local/bin/cloudflared
                sudo chmod +x /usr/local/bin/cloudflared
            }
            ;;
        *)
            curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}" -o /usr/local/bin/cloudflared
            sudo chmod +x /usr/local/bin/cloudflared
            ;;
    esac
fi

if command -v cloudflared &>/dev/null; then
    log "Cloudflared installed"
else
    warn "Cloudflared install failed - tunnel won't work"
fi

# ─── Tunnel Script ───
header "Tunnel"

sudo tee "$TUNNEL_SCRIPT" >/dev/null <<'EOF'
#!/bin/bash
KIRO_DIR="$HOME/.kiro-gateway"
mkdir -p "$KIRO_DIR"

start_tunnel() {
    local port=$1
    local label=$2
    local logfile="/var/log/kiro-gateway-tunnel-${label}.log"
    local urlfile="$KIRO_DIR/${label}_url.txt"

    > "$logfile"
    cloudflared tunnel --url "http://localhost:${port}" --no-autoupdate >> "$logfile" 2>&1 &
    local pid=$!

    for i in $(seq 1 30); do
        sleep 2
        local url=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' "$logfile" 2>/dev/null | tail -1)
        if [[ -n "$url" ]]; then
            echo "$url" > "$urlfile"
            echo "[$(date)] ${label}: $url" >> "$KIRO_DIR/tunnel_history.txt"
            break
        fi
    done
    echo $pid
}

while true; do
    pkill -f "cloudflared tunnel --url http://localhost:8001" 2>/dev/null || true
    sleep 1

    > /var/log/kiro-gateway-tunnel-api.log

    API_PID=$(start_tunnel 8001 api)

    while kill -0 $API_PID 2>/dev/null; do
        sleep 10
    done

    sleep 5
done
EOF
sudo chmod +x "$TUNNEL_SCRIPT"

if command -v systemctl &>/dev/null; then
    sudo tee /etc/systemd/system/kiro-gateway-tunnel.service >/dev/null <<EOF
[Unit]
Description=Kiro Gateway Cloudflare Tunnel
After=network-online.target kiro-gateway.service
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
    sudo systemctl enable --now kiro-gateway-tunnel
    log "Tunnel service enabled"
else
    nohup "$TUNNEL_SCRIPT" > "$KIRO_DIR/tunnel.log" 2>&1 &
    log "Tunnel running in background"
fi

# Wait for tunnel URL
info "Waiting for tunnel URL..."
for i in $(seq 1 30); do
    [[ -f "$KIRO_DIR/api_url.txt" ]] && break
    sleep 2
done

API_URL=$(cat "$KIRO_DIR/api_url.txt" 2>/dev/null || echo "loading...")

# ─── Summary ───
echo ""
echo -e "  ${BOLD}${GREEN}Done${NC}"
echo -e "  ${DIM}$(printf '%.0s━' $(seq 1 50))${NC}"
echo ""
echo -e "  ${BOLD}Local API${NC}    ${CYAN}http://localhost:8001/v1${NC}"
echo -e "  ${BOLD}Tunnel API${NC}   ${CYAN}${API_URL}/v1${NC}"
echo -e "  ${BOLD}API Key${NC}      ${YELLOW}${PROXY_KEY}${NC}"
echo -e "  ${BOLD}Accounts${NC}     ${DIM}${ACCOUNT_COUNT:-0} loaded${NC}"
echo ""
echo -e "  ${DIM}Usage with Claude Code / OpenAI clients:${NC}"
echo -e "  ${DIM}  Base URL: ${API_URL}/v1${NC}"
echo -e "  ${DIM}  API Key:  ${PROXY_KEY}${NC}"
echo -e "  ${DIM}  Model:    claude-opus-4.6${NC}"
echo ""
echo -e "  ${DIM}Commands:${NC}"
echo -e "  ${DIM}  cat ~/.kiro-gateway/api_url.txt${NC}              ${DIM}check tunnel URL${NC}"
echo -e "  ${DIM}  sudo systemctl restart kiro-gateway${NC}          ${DIM}restart gateway${NC}"
echo -e "  ${DIM}  sudo systemctl restart kiro-gateway-tunnel${NC}   ${DIM}restart tunnel${NC}"
echo -e "  ${DIM}  sudo journalctl -u kiro-gateway -f${NC}           ${DIM}view logs${NC}"
echo ""
echo -e "  ${DIM}Add accounts:${NC}"
echo -e "  ${DIM}  Edit ~/.kiro-gateway/repo/credentials.json${NC}"
echo -e "  ${DIM}  Then: sudo systemctl restart kiro-gateway${NC}"
echo ""
