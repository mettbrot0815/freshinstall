#!/bin/bash
set -euo pipefail  # strict mode: unset vars & pipe errors also exit

# ── Config ───────────────────────────────────────
readonly HOME="$HOME"
readonly MODEL="mistralai/Mistral-7B-Instruct-v0.3"
readonly LOG="$HOME/logs/lm-openwebui-setup_$(date +%Y%m%d_%H%M).log"

mkdir -p "$HOME/logs" || { echo "[!] Cannot create logs dir" >&2; exit 1; }
exec 1> >(tee -a "$LOG") 2>&1   # redirect all output to log + stdout

echo "[+] Started: $(date)"

err() { echo "[!] ERROR: $1" >&2; exit 1; }

cmd_exists() { command -v "$1" >/dev/null 2>&1; }

# ── Prerequisites ────────────────────────────────
echo "[+] Updating system & installing basics..."
sudo apt update -yq || err "apt update failed"
sudo apt upgrade -yq || err "apt upgrade failed"
sudo apt install -y --no-install-recommends \
    curl git jq net-tools ca-certificates \
    software-properties-common apt-transport-https lsb-release \
    || err "Prerequisites installation failed"

# ── Docker ───────────────────────────────────────
echo "[+] Setting up Docker..."
if ! cmd_exists docker; then
    echo "[+] Installing Docker..."
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | sudo gpg --dearmor -o /usr/share/keyrings/docker.gpg \
        || err "Failed to fetch Docker GPG key"

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
        | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null \
        || err "Failed to add Docker repo"

    sudo apt update -yq || err "apt update after Docker repo failed"
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin \
        || err "Docker package installation failed"

    sudo systemctl enable --now docker || err "Failed to start/enable Docker"
    sudo usermod -aG docker "$USER" || echo "[!] Warning: usermod -aG docker failed (non-fatal)"
    echo "[!] Docker group added → run 'newgrp docker' or re-login for changes to take effect"
else
    echo "[+] Docker already installed"
fi

# ── LM Studio ────────────────────────────────────
echo "[+] Installing LM Studio..."
if ! cmd_exists lms && ! cmd_exists lmstudio; then
    echo "[+] Running official installer..."
    curl -fsSL https://lmstudio.ai/install.sh | bash || err "LM Studio install script failed"
    sleep 2
    if ! cmd_exists lms; then
        echo "[!] Warning: 'lms' command not found after install – may need re-login or manual check"
    else
        echo "[+] LM Studio / lms CLI installed"
    fi
else
    echo "[+] LM Studio appears already installed"
fi

# ── Open WebUI ───────────────────────────────────
echo "[+] Preparing Open WebUI..."
cd "$HOME" || err "Cannot cd to home"

# Clean old instances safely
docker stop open-webui >/dev/null 2>&1 || true
docker rm open-webui >/dev/null 2>&1 || true
docker volume rm open-webui-data >/dev/null 2>&1 || true

cat > docker-compose.yml <<'EOF' || err "Failed to write docker-compose.yml"
version: '3.8'
services:
  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: open-webui
    ports: ["3000:8080"]
    volumes: [open-webui-data:/app/backend/data]
    extra_hosts: [host.docker.internal:host-gateway]
    environment:
      - OLLAMA_BASE_URL=http://host.docker.internal:1234/v1
    restart: unless-stopped
EOF

cat > start.sh <<'EOF' || err "Failed to write start.sh"
#!/bin/bash
echo ""
echo "1. Open LM Studio (search 'lmstudio' or run it)"
echo "   → Download / load '$MODEL'"
echo "   → Local Server tab → Start Server (port 1234)"
echo ""
echo "2. Starting Open WebUI..."
docker compose down 2>/dev/null || true
docker compose up -d || { echo "[!] docker compose up failed"; exit 1; }
sleep 25
if curl -sI http://localhost:3000 | grep -q "200"; then
    echo ""
    echo "→ Open WebUI ready at: http://localhost:3000"
    echo "First time: create account → Settings → Connections → URL = http://localhost:1234/v1"
else
    echo "[!] Open WebUI not responding yet"
    echo "   Check logs: docker logs open-webui"
    echo "   Or status: docker ps | grep open-webui"
fi
EOF
chmod +x start.sh || err "chmod start.sh failed"

# ── Final instructions ───────────────────────────
cat > README_AI.md <<EOF || err "Failed to write README"
Local AI Stack (LM Studio + Open WebUI)

Quick start:
1. newgrp docker   (or log out/in)
2. Launch LM Studio → download $MODEL → Start Server
3. Run: ./start.sh

Browser → http://localhost:3000

Troubleshoot:
- No models?     LM Studio server not running
- Permission?    newgrp docker / re-login
- Port conflict? Edit docker-compose.yml ports
EOF

echo ""
echo "============================================="
echo "            Setup complete!"
echo "============================================="
echo ""
echo "Next steps:"
echo "  1. newgrp docker    (or log out + back in)"
echo "  2. Start LM Studio → download/load '$MODEL' → Start Server"
echo "  3. ./start.sh"
echo ""
echo "Guide: $HOME/README_AI.md"
echo "Log:   $LOG"
echo ""
