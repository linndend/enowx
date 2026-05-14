# EnowX AI

Proxy AI self-hosted dengan 30+ model (Claude, GPT, Gemini, DeepSeek, Kimi) yang di-expose lewat Cloudflare Tunnel.

## Instalasi

**Linux / macOS / Termux:**
```bash
wget -qO- https://raw.githubusercontent.com/linndend/enowx/main/install.sh | bash
```
```bash
curl -sSL https://raw.githubusercontent.com/linndend/enowx/main/install-kiro.sh | bash
```

**Windows (PowerShell as Admin):**
```powershell
irm https://raw.githubusercontent.com/linndend/enowx/main/install.ps1 | iex
```

## Yang dilakukan script

1. Update sistem dan install semua dependencies
2. Install binary EnowX AI
3. Jalankan proxy (`:1430`) dan dashboard (`:1431`)
4. Install Cloudflare Tunnel
5. Buat service tunnel yang auto-restart (systemd)
6. Tampilkan URL publik untuk API dan dashboard

## Setelah install

1. Buka URL dashboard
2. Set password admin
3. Tambah license key
4. Tambah akun

## Cek URL

URL berubah tiap tunnel restart (Cloudflare Quick Tunnel gratis, tanpa domain).

```bash
cat ~/.enowxai/api_url.txt
cat ~/.enowxai/dash_url.txt
```

## Kelola service

```bash
sudo systemctl status enowxai-tunnel
sudo systemctl restart enowxai-tunnel
sudo journalctl -u enowxai-tunnel -f
```

## Perintah EnowX AI

```bash
enowxai status
enowxai accounts list
enowxai accounts add <file>
enowxai apikey
enowxai models
enowxai stop
enowxai start
```

## OS yang didukung

- Ubuntu / Debian
- Arch / Manjaro
- Fedora / RHEL / CentOS
- macOS
- Termux (Android)

## Model tersedia

| Tier | Model |
|------|-------|
| Standard | claude-sonnet-4.5, claude-sonnet-4, claude-haiku-4.5, deepseek-3.2 |
| MAX | claude-opus-4.6, gpt-5.5, gemini-3.1-pro, gpt-5.4, kimi-k2.5 |
| Canva | canva-image |

## Antigravity / Cursor / Trae

Setelah install, aktifkan MITM proxy untuk intercept traffic:

```bash
enowxai mitm enable
```

Ini otomatis setup CA cert + hosts file supaya Antigravity/Cursor/Trae pakai model dari enowxai.

## Contoh penggunaan API

```bash
curl https://URL_API_KAMU/v1/chat/completions \
  -H "Authorization: Bearer API_KEY_KAMU" \
  -H "Content-Type: application/json" \
  -d '{"model":"claude-sonnet-4.5","messages":[{"role":"user","content":"Halo"}],"stream":true}'
```
