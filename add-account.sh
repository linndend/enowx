#!/bin/bash
CREDS_FILE="${KIRO_DIR:-$HOME/.kiro-gateway/repo}/credentials.json"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

# Accept token from argument or prompt
if [[ -n "$1" ]]; then
    TOKEN="$1"
else
    echo -e "  ${BOLD}Refresh Token:${NC}"
    read -r -p "  > " TOKEN
fi

if [[ -z "$TOKEN" ]]; then
    echo -e "  ${RED}●${NC} Token kosong"; exit 1
fi

# Validate token
echo -e "  ${DIM}Validating token...${NC}"
RESULT=$(curl -s -X POST "https://prod.us-east-1.auth.desktop.kiro.dev/refreshToken" \
    -H "Content-Type: application/json" \
    -d "{\"refreshToken\": \"$TOKEN\"}" 2>/dev/null)

if echo "$RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); exit(0 if 'accessToken' in d else 1)" 2>/dev/null; then
    echo -e "  ${GREEN}●${NC} Token valid"
else
    echo -e "  ${RED}●${NC} Token invalid atau expired"
    exit 1
fi

# Add to credentials.json
python3 -c "
import json, sys

creds_file = '$CREDS_FILE'
token = sys.argv[1]

try:
    with open(creds_file) as f:
        creds = json.load(f)
except:
    creds = []

# Check duplicate
for c in creds:
    if c.get('refresh_token') == token:
        print('  Already exists')
        sys.exit(0)

creds.append({'type': 'refresh_token', 'refresh_token': token, 'region': 'us-east-1'})

with open(creds_file, 'w') as f:
    json.dump(creds, f, indent=2)

print(f'  Added. Total accounts: {len(creds)}')
" "$TOKEN"

# Restart gateway if systemd
if systemctl is-active --quiet kiro-gateway 2>/dev/null; then
    sudo systemctl restart kiro-gateway
    echo -e "  ${GREEN}●${NC} Gateway restarted"
fi
