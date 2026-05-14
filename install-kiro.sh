#!/bin/bash
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

KIRO_DIR="$HOME/.kiro-gateway"

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
echo -e "  ${DIM}Multi account proxy for Kiro API${NC}"
echo ""

if [[ -n "$1" ]]; then
    CUSTOM_API_KEY="$1"
elif [[ -n "$KIRO_API_KEY" ]]; then
    CUSTOM_API_KEY="$KIRO_API_KEY"
else
    echo -e "  ${BOLD}API Key${NC} ${DIM}(isi atau kosongkan untuk generate otomatis):${NC}"
    read -r -p "  > " CUSTOM_API_KEY
fi

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

header "Python Environment"

if [[ ! -d "$KIRO_DIR/venv" ]]; then
    python3 -m venv "$KIRO_DIR/venv"
fi
source "$KIRO_DIR/venv/bin/activate"
pip install -q --upgrade pip
pip install -q -r requirements.txt
log "Dependencies installed"

header "Configuration"

if [[ ! -f "$KIRO_DIR/repo/.env" ]]; then
    if [[ -n "$CUSTOM_API_KEY" ]]; then
        PROXY_KEY="$CUSTOM_API_KEY"
        log "Using provided API key"
    else
        PROXY_KEY=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")
        log "Generated random API key"
    fi
    cat > "$KIRO_DIR/repo/.env" <<EOF
PROXY_API_KEY="${PROXY_KEY}"
KIRO_REGION="us-east-1"
SERVER_HOST="0.0.0.0"
SERVER_PORT="8001"
LOG_LEVEL="INFO"
EOF
else
    PROXY_KEY=$(grep PROXY_API_KEY "$KIRO_DIR/repo/.env" | cut -d'"' -f2)
    if [[ -n "$CUSTOM_API_KEY" && "$PROXY_KEY" != "$CUSTOM_API_KEY" ]]; then
        sed -i "s/PROXY_API_KEY=.*/PROXY_API_KEY=\"${CUSTOM_API_KEY}\"/" "$KIRO_DIR/repo/.env"
        PROXY_KEY="$CUSTOM_API_KEY"
        log "API key updated"
    else
        log ".env already exists"
    fi
fi

if [[ ! -f "$KIRO_DIR/repo/credentials.json" ]]; then
    echo "[]" > "$KIRO_DIR/repo/credentials.json"
    warn "credentials.json is empty - add accounts later"
else
    ACCOUNT_COUNT=$(python3 -c "import json; print(len(json.load(open('$KIRO_DIR/repo/credentials.json'))))" 2>/dev/null || echo "0")
    log "credentials.json: ${ACCOUNT_COUNT} accounts"
fi

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
    nohup "$KIRO_DIR/venv/bin/python" "$KIRO_DIR/repo/main.py" > "$KIRO_DIR/gateway.log" 2>&1 &
    echo $! > "$KIRO_DIR/gateway.pid"
    log "Running in background (PID: $(cat $KIRO_DIR/gateway.pid))"
fi

sleep 2

if curl -s http://localhost:8001/health >/dev/null 2>&1; then
    log "Gateway is running on port 8001"
else
    warn "Gateway may still be starting..."
fi

echo ""
echo -e "  ${BOLD}${GREEN}Done${NC}"
echo -e "  ${DIM}$(printf '%.0s━' $(seq 1 50))${NC}"
echo ""
echo -e "  ${BOLD}API URL${NC}    ${CYAN}http://localhost:8001/v1${NC}"
echo -e "  ${BOLD}API Key${NC}    ${YELLOW}${PROXY_KEY}${NC}"
echo -e "  ${BOLD}Accounts${NC}   ${DIM}${ACCOUNT_COUNT:-0} loaded${NC}"
echo ""
echo -e "  ${DIM}Usage:${NC}"
echo -e "  ${DIM}  Base URL: http://localhost:8001/v1${NC}"
echo -e "  ${DIM}  API Key:  ${PROXY_KEY}${NC}"
echo -e "  ${DIM}  Model:    claude-opus-4.6${NC}"
echo ""
echo -e "  ${DIM}Commands:${NC}"
echo -e "  ${DIM}  sudo systemctl restart kiro-gateway${NC}   restart gateway${NC}"
echo -e "  ${DIM}  sudo journalctl -u kiro-gateway -f${NC}    view logs${NC}"
echo ""
echo -e "  ${DIM}Add accounts:${NC}"
echo -e "  ${DIM}  Edit ~/.kiro-gateway/repo/credentials.json${NC}"
echo -e "  ${DIM}  Then: sudo systemctl restart kiro-gateway${NC}"
echo ""
echo -e "  ${DIM}Change API key:${NC}"
echo -e "  ${DIM}  bash install-kiro.sh mynewkey${NC}"
echo -e "  ${DIM}  or: KIRO_API_KEY=mynewkey bash install-kiro.sh${NC}"
echo ""
