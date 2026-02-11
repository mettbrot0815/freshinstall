#!/bin/bash

# Exit on error (but we'll handle critical parts carefully)
set -e

# Configuration
USER_HOME="$HOME"
LOG_DIR="$USER_HOME/logs"
INSTALL_LOG="$LOG_DIR/openwebui_lmstudio_install_$(date +%Y%m%d_%H%M%S).log"
MODEL_NAME="mistralai/Mistral-7B-Instruct-v0.3"   # Note: case-sensitive on HF, but LM Studio normalizes

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Functions
log()      { echo -e "${GREEN}[INFO]${NC} $1"  | tee -a "$INSTALL_LOG"; }
warn()     { echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$INSTALL_LOG"; }
err()      { echo -e "${RED}[ERROR]${NC} $1"  | tee -a "$INSTALL_LOG"; exit 1; }

check_cmd() {
    command -v "$1" &>/dev/null || err "$1 not found. Please install it."
}

# ────────────────────────────────────────────────
# Start
# ────────────────────────────────────────────────

mkdir -p "$LOG_DIR" || err "Cannot create log dir"
touch "$INSTALL_LOG" || err "Cannot create log file"
log "Installation started: $(date)"
log "Log → $INSTALL_LOG"

# Update & prerequisites
log "Updating system & installing prerequisites..."
sudo apt update -y  >>"$INSTALL_LOG" 2>&1
sudo apt upgrade -y >>"$INSTALL_LOG" 2>&1
sudo apt install -y curl wget git jq net-tools \
    python3-pip python3-venv build-essential \
    ca-certificates software-properties-common \
    apt-transport-https lsb-release >>"$INSTALL_LOG" 2>&1 || err "Prerequisites failed"

# Docker
log "Setting up Docker..."
if ! command -v docker &>/dev/null; then
    sudo apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | sudo gpg --dearmor -o /usr/share/keyrings/docker.gpg \
        || err "Docker GPG key failed"

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
        | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

    sudo apt update -y >>"$INSTALL_LOG" 2>&1
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin >>"$INSTALL_LOG" 2>&1 || err "Docker install failed"

    sudo systemctl enable --now docker >>"$INSTALL_LOG" 2>&1
    sudo usermod -aG docker "$USER" || warn "usermod docker group failed (non-fatal)"
    warn "Docker group added → run 'newgrp docker' or log out/in"
else
    log "Docker already installed"
fi

# LM Studio (2026 recommended method)
log "Installing LM Studio via official script..."
if ! command -v lmstudio &>/dev/null && [ ! -f "/usr/local/bin/lmstudio" ]; then
    curl -fsSL https://lmstudio.ai/install.sh | bash >>"$INSTALL_LOG" 2>&1 || err "LM Studio install script failed"
    
    # Give it a moment and check
    sleep 3
    if ! command -v lmstudio &>/dev/null; then
        warn "lmstudio command not found after install – you may need to restart terminal or check ~/bin / /usr/local/bin"
    else
        log "LM Studio installed (command: lmstudio)"
    fi
else
    log "LM Studio appears already installed"
fi

# Open WebUI via Docker
log "Setting up Open WebUI..."

cd "$USER_HOME" || err "Cannot cd to home"

# Clean old
docker stop open-webui 2>/dev/null || true
docker rm open-webui 2>/dev/null || true
docker volume rm open-webui-data 2>/dev/null || true

cat > docker-compose.yml << 'EOF'
version: '3.8'
services:
  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: open-webui
    ports:
      - "3000:8080"
    volumes:
      - open-webui-data:/app/backend/data
    extra_hosts:
      - "host.docker.internal:host-gateway"
    environment:
      - OLLAMA_BASE_URL=http://host.docker.internal:1234/v1
      - WEBUI_SECRET_KEY=  # optional – set if you want
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/api/health"]
      interval: 30s
      timeout: 10s
      retries: 3
volumes:
  open-webui-data:
EOF

# Startup helper scripts
cat > start_openwebui.sh << 'EOF'
#!/bin/bash
cd "$HOME"
echo "Starting Open WebUI..."
docker compose down 2>/dev/null
docker compose up -d
echo "Waiting 40s..."
sleep 40
if curl -sI http://localhost:3000 | grep -q "200"; then
    echo -e "\nOpen WebUI should be at: http://localhost:3000"
    echo "If first time → create account, then Settings → Connections → URL = http://localhost:1234/v1"
else
    echo "Not responding yet. Check: docker logs open-webui"
fi
EOF
chmod +x start_openwebui.sh

cat > start_all.sh << 'EOF'
#!/bin/bash
echo ""
echo "=== Local AI Stack Starter ==="
echo ""
echo "1. Start LM Studio manually:"
echo "   • Open LM Studio (search 'lmstudio' in menu or run 'lmstudio')"
echo "   • Download model: $MODEL_NAME (search in Discover tab)"
echo "   • Load the model"
echo "   • Developer / Local Server tab → Start Server (port 1234)"
echo "   • Wait until 'Server running'"
echo ""
echo "2. Starting Open WebUI..."
bash "$HOME/start_openwebui.sh"
echo ""
echo "Access → http://localhost:3000"
echo "Verify → docker ps | grep open-webui"
echo "LM Studio API → curl http://localhost:1234/v1/models"
echo ""
EOF
chmod +x start_all.sh

cat > verify.sh << 'EOF'
#!/bin/bash
echo "Verification (run after LM Studio server started)"
echo "Docker     : $(docker --version || echo 'not found')"
echo "Open WebUI : $(docker ps -q -f name=open-webui && echo 'running' || echo 'not running')"
echo "LM API     : $(curl -s http://localhost:1234/v1/models | jq . 2>/dev/null || echo 'not responding')"
echo "WebUI page : $(curl -sI http://localhost:3000 | head -1)"
EOF
chmod +x verify.sh

# Final instructions
cat > AI_STACK_README.md << EOF
# Local AI Stack (LM Studio + Open WebUI)

Installed:
- Docker & Compose
- LM Studio (via official 2026 installer)
- Open WebUI (Docker)

**One-time manual steps**
1. Open LM Studio → download **$MODEL_NAME** (or any model you like)
2. Load model → Start Server (port 1234)

**Usage**
./start_all.sh          → starts Open WebUI (after you started LM Studio server)
./verify.sh             → quick status check

Browser: http://localhost:3000
Create account first time
Settings → Connections → OpenAI API → URL = http://localhost:1234/v1

Troubleshooting
- No models? → ensure LM Studio server is running
- Docker permission? → newgrp docker  or re-login
- Port 3000 used? → edit docker-compose.yml

Logs: $LOG_DIR
EOF

log "Installation finished!"
echo
echo "================================================"
echo "               Setup mostly done!"
echo "================================================"
echo
echo "Next:"
echo "1. Run:  newgrp docker    (or log out/in)"
echo "2. Open LM Studio → download & start server with $MODEL_NAME"
echo "3. Then:  ./start_all.sh"
echo
echo "Full guide → $USER_HOME/AI_STACK_README.md"
echo "Log        → $INSTALL_LOG"
echo
echo "(LM Studio install is now script-based → should survive version updates better)"