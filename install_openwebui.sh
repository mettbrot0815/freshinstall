#!/bin/bash
set -e

# ── Config ───────────────────────────────────────
HOME="$HOME"
MODEL="mistralai/Mistral-7B-Instruct-v0.3"
LOG="$HOME/logs/lm-openwebui-setup_$(date +%Y%m%d_%H%M).log"
mkdir -p "$HOME/logs"

log() { echo "[+] $1" | tee -a "$LOG"; }
err() { echo "[!] $1" >&2 | tee -a "$LOG"; exit 1; }

# ── Prerequisites ────────────────────────────────
log "Updating & installing basics..."
sudo apt update -yq && sudo apt upgrade -yq
sudo apt install -y curl git jq net-tools ca-certificates \
    software-properties-common apt-transport-https lsb-release

# ── Docker ───────────────────────────────────────
log "Docker..."
if ! command -v docker >/dev/null; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
    sudo apt update -yq
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    sudo systemctl enable --now docker
    sudo usermod -aG docker "$USER"
    echo "→ Run 'newgrp docker' or re-login"
fi

# ── LM Studio ────────────────────────────────────
log "LM Studio..."
if ! command -v lms >/dev/null; then
    curl -fsSL https://lmstudio.ai/install.sh | bash || err "LM Studio install failed"
    log "Installed (use 'lmstudio' for GUI or 'lms' for CLI)"
else
    log "Already installed"
fi

# ── Open WebUI ───────────────────────────────────
log "Open WebUI..."
cd "$HOME"

# Clean old
docker stop open-webui 2>/dev/null || true
docker rm open-webui 2>/dev/null || true
docker volume rm open-webui-data 2>/dev/null || true

cat > docker-compose.yml <<'EOF'
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

cat > start.sh <<'EOF'
#!/bin/bash
echo "1. Open LM Studio → download/load '$MODEL' → Start Server (port 1234)"
echo "2. Starting Open WebUI..."
docker compose down 2>/dev/null
docker compose up -d
sleep 25
if curl -sI http://localhost:3000 | grep -q 200; then
    echo "→ http://localhost:3000  (first time: create account → Settings → Connections → URL = http://localhost:1234/v1)"
else
    echo "Not ready — check: docker logs open-webui"
fi
EOF
chmod +x start.sh

# ── Quick README ─────────────────────────────────
cat > README_AI.md <<EOF
Local AI (LM Studio + Open WebUI)

Run:
  ./start.sh     (after starting LM Studio server)

Access: http://localhost:3000

First time:
1. LM Studio → download $MODEL
2. Load model → Start Server
3. Run ./start.sh
4. In Open WebUI → Settings → Connections → http://localhost:1234/v1

Troubleshoot:
- Docker perms → newgrp docker / re-login
- No models → LM Studio server must run
EOF

log "Done!"
cat <<'END'

============================================
             Setup complete!
============================================

Next:
1. newgrp docker   (or log out/in)
2. Open LM Studio  → download & start server with $MODEL
3. ./start.sh

See README_AI.md
Log: $LOG
END
