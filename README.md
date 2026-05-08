# EnowX AI

Self-hosted AI proxy with 30+ models (Claude, GPT, Gemini, DeepSeek, Kimi) exposed via Cloudflare Tunnel.

## Install

```bash
wget -qO- https://raw.githubusercontent.com/linndend/enowx/main/install.sh | bash
```

## What it does

1. Updates system and installs dependencies
2. Installs EnowX AI binary
3. Starts proxy (`:1430`) and dashboard (`:1431`)
4. Installs Cloudflare Tunnel
5. Creates auto-restart tunnel service (systemd)
6. Outputs public URLs for API and dashboard

## After install

1. Open dashboard URL
2. Set admin password
3. Add license key
4. Add accounts

## Check URLs

URLs change on tunnel restart (free Cloudflare Quick Tunnel).

```bash
cat ~/.enowxai/api_url.txt
cat ~/.enowxai/dash_url.txt
```

## Service management

```bash
sudo systemctl status enowxai-tunnel
sudo systemctl restart enowxai-tunnel
sudo journalctl -u enowxai-tunnel -f
```

## EnowX AI commands

```bash
enowxai status
enowxai accounts list
enowxai accounts add <file>
enowxai apikey
enowxai models
enowxai stop
enowxai start
```

## Supported OS

- Ubuntu / Debian
- Arch / Manjaro
- Fedora / RHEL / CentOS
- macOS
- Termux (Android)

## Models

| Tier | Models |
|------|--------|
| Standard | claude-sonnet-4.5, claude-sonnet-4, claude-haiku-4.5, deepseek-3.2 |
| MAX | claude-opus-4.6, gpt-5.5, gemini-3.1-pro, gpt-5.4, kimi-k2.5 |
| Canva | canva-image |

## API usage

```bash
curl https://YOUR_API_URL/v1/chat/completions \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"claude-sonnet-4.5","messages":[{"role":"user","content":"Hello"}],"stream":true}'
```
