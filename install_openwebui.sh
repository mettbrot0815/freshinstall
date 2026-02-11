#!/bin/bash

# Exit on error
set -e

# Configuration
USER_HOME="$HOME"
LOG_DIR="$USER_HOME/logs"
INSTALL_LOG="$LOG_DIR/openwebui_install_$(date +%Y%m%d_%H%M%S).log"
LM_STUDIO_URL="https://releases.lmstudio.ai/linux/x86_64/latest"
LM_STUDIO_DEB="LM_Studio-latest-x86_64-linux.deb"
MODEL_NAME="mistralai/mistral-7b-instruct-v0.3"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions
log_message() {
    echo -e "${GREEN}[INFO]${NC} $1" | tee -a "$INSTALL_LOG"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$INSTALL_LOG"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$INSTALL_LOG"
    exit 1
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "$1 is not installed. Please install it first."
    fi
}

# Create log directory
mkdir -p "$LOG_DIR"
touch "$INSTALL_LOG"
log_message "Installation started at $(date)"
log_message "Log file: $INSTALL_LOG"

# Update system
log_message "Updating system packages..."
sudo apt update -y >> "$INSTALL_LOG" 2>&1
sudo apt upgrade -y >> "$INSTALL_LOG" 2>&1

# Install prerequisites
log_message "Installing prerequisites..."
sudo apt install -y curl wget git python3-pip python3-venv build-essential \
    software-properties-common apt-transport-https ca-certificates \
    gnupg lsb-release jq net-tools >> "$INSTALL_LOG" 2>&1

# Install Docker
log_message "Installing Docker..."
if ! command -v docker &> /dev/null; then
    # Remove old versions
    sudo apt remove -y docker docker-engine docker.io containerd runc >> "$INSTALL_LOG" 2>&1
    
    # Add Docker repository
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg >> "$INSTALL_LOG" 2>&1
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    sudo apt update -y >> "$INSTALL_LOG" 2>&1
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin >> "$INSTALL_LOG" 2>&1
    
    # Start Docker and enable on boot
    sudo systemctl start docker >> "$INSTALL_LOG" 2>&1
    sudo systemctl enable docker >> "$INSTALL_LOG" 2>&1
    
    # Add user to docker group
    sudo usermod -aG docker "$USER" >> "$INSTALL_LOG" 2>&1
    log_warning "User added to docker group. You may need to log out and back in or run: newgrp docker"
else
    log_message "Docker is already installed"
fi

# Install LM Studio
log_message "Installing LM Studio..."
if ! command -v lmstudio &> /dev/null; then
    # Download LM Studio
    cd "$USER_HOME"
    wget -O "$LM_STUDIO_DEB" "$LM_STUDIO_URL" >> "$INSTALL_LOG" 2>&1 || log_error "Failed to download LM Studio"
    
    # Install dependencies
    sudo apt install -y libfuse2 libnss3 libgtk-3-0 libxss1 libasound2 >> "$INSTALL_LOG" 2>&1
    
    # Install LM Studio
    sudo dpkg -i "$LM_STUDIO_DEB" >> "$INSTALL_LOG" 2>&1 || sudo apt install -f -y >> "$INSTALL_LOG" 2>&1
    
    # Clean up
    rm -f "$LM_STUDIO_DEB"
    
    log_message "LM Studio installed. You'll need to start it manually to download models."
else
    log_message "LM Studio is already installed"
fi

# Download a model for LM Studio
log_message "Setting up model directory..."
LM_MODEL_DIR="$USER_HOME/.cache/lm-studio/models"
mkdir -p "$LM_MODEL_DIR"

# Create LM Studio config
log_message "Creating LM Studio configuration..."
cat > "$USER_HOME/lmstudio_startup.sh" << EOF
#!/bin/bash
# Start LM Studio with server
/opt/LM_Studio/lmstudio --no-sandbox &
sleep 10

echo "LM Studio started. Please:"
echo "1. Wait for LM Studio to open"
echo "2. Go to 'Local Server' tab"
echo "3. Click 'Start Server'"
echo "4. Download model: $MODEL_NAME"
echo ""
echo "Once server is running, Open WebUI will be available at: http://localhost:3000"
EOF

chmod +x "$USER_HOME/lmstudio_startup.sh"

# Install Open WebUI
log_message "Installing Open WebUI..."
cd "$USER_HOME"

# Stop and remove any existing Open WebUI containers
docker stop open-webui 2>/dev/null || true
docker rm open-webui 2>/dev/null || true
docker volume rm open-webui-data 2>/dev/null || true

# Create docker-compose configuration
cat > "$USER_HOME/docker-compose.yml" << EOF
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
      - OLLAMA_BASE_URL=http://host.docker.internal:1234/api/v1
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/api/health"]
      interval: 30s
      timeout: 10s
      retries: 3

volumes:
  open-webui-data:
EOF

# Create startup script for Open WebUI
cat > "$USER_HOME/start_openwebui.sh" << EOF
#!/bin/bash
# Start Open WebUI
echo "Starting Open WebUI..."
cd "$USER_HOME"
docker-compose down 2>/dev/null
docker-compose up -d

echo "Waiting for Open WebUI to start..."
sleep 30

# Check if it's running
if curl -s http://localhost:3000 > /dev/null; then
    echo "Open WebUI is running at: http://localhost:3000"
    echo ""
    echo "First-time setup:"
    echo "1. Go to http://localhost:3000"
    echo "2. Create an account"
    echo "3. Go to Settings -> Connections"
    echo "4. Set URL to: http://localhost:1234/api/v1"
    echo "5. Save and refresh models"
else
    echo "Open WebUI failed to start. Check logs with: docker logs open-webui"
fi
EOF

chmod +x "$USER_HOME/start_openwebui.sh"

# Create complete startup script
cat > "$USER_HOME/start_all.sh" << EOF
#!/bin/bash
echo "Starting AI Stack..."
echo "===================="
echo ""

# Start LM Studio (manual instructions)
echo "1. Please start LM Studio manually:"
echo "   - Open LM Studio from applications menu"
echo "   - Load model: $MODEL_NAME"
echo "   - Click 'Start Server' (bottom left)"
echo "   - Wait for 'Server running on port 1234'"
echo ""

# Start Open WebUI
echo "2. Starting Open WebUI..."
bash "$USER_HOME/start_openwebui.sh"

echo ""
echo "Access:"
echo "- Open WebUI: http://localhost:3000"
echo "- LM Studio API: http://localhost:1234/api/v1/models"
EOF

chmod +x "$USER_HOME/start_all.sh"

# Create verification script
cat > "$USER_HOME/verify_installation.sh" << EOF
#!/bin/bash
echo "=== Verification Script ==="
echo "Run this after starting LM Studio server"
echo ""
echo "1. Checking Docker..."
docker --version && echo "✓ Docker installed" || echo "✗ Docker not found"
echo ""
echo "2. Checking Open WebUI..."
docker ps | grep open-webui && echo "✓ Open WebUI running" || echo "✗ Open WebUI not running"
echo ""
echo "3. Checking LM Studio API..."
if curl -s http://localhost:1234/api/v1/models > /dev/null 2>&1; then
    echo "✓ LM Studio API responding"
    curl -s http://localhost:1234/api/v1/models | jq '.models[0].display_name' 2>/dev/null || echo "  Models available"
else
    echo "✗ LM Studio API not responding"
    echo "  Make sure LM Studio server is started"
fi
echo ""
echo "4. Checking Open WebUI access..."
if curl -s http://localhost:3000 > /dev/null 2>&1; then
    echo "✓ Open WebUI accessible"
else
    echo "✗ Open WebUI not accessible"
fi
EOF

chmod +x "$USER_HOME/verify_installation.sh"

# Create README
cat > "$USER_HOME/AI_STACK_README.txt" << EOF
AI Stack Installation Complete!
===============================

What was installed:
1. Docker & Docker Compose
2. LM Studio (local AI model runner)
3. Open WebUI (ChatGPT-like interface)
4. Mistral 7B model configuration

Files created:
- start_all.sh          - Main startup script
- start_openwebui.sh    - Start Open WebUI only
- verify_installation.sh - Check everything is working
- docker-compose.yml    - Open WebUI configuration
- lmstudio_startup.sh   - LM Studio startup helper

HOW TO USE:
===========

1. FIRST TIME: Download a model
   - Open LM Studio from applications menu
   - Search for "mistralai/mistral-7b-instruct-v0.3"
   - Download it

2. Start LM Studio server:
   - In LM Studio, load the model
   - Click "Start Server" (bottom left)
   - Wait for "Server running on port 1234"

3. Start Open WebUI:
   - Run: ./start_all.sh
   - OR: ./start_openwebui.sh

4. Access Open WebUI:
   - Browser: http://localhost:3000
   - Create account
   - Configure connection:
        Settings -> Connections -> URL: http://localhost:1234/api/v1

5. Verify installation:
   - Run: ./verify_installation.sh

TROUBLESHOOTING:
================
- If Open WebUI shows "Backend Required": Wait 60 seconds, it's still starting
- If no models appear: Make sure LM Studio server is running
- Docker permission errors: Run: newgrp docker
- Port conflicts: Edit docker-compose.yml to change port 3000

Logs: $LOG_DIR
EOF

# Set permissions
sudo chown -R "$USER:$USER" "$USER_HOME"

# Final steps
log_message "Installation complete!"
log_message ""
log_message "NEXT STEPS:"
log_message "1. Log out and back in (or run: newgrp docker)"
log_message "2. Start LM Studio and download model: $MODEL_NAME"
log_message "3. Run: ./start_all.sh"
log_message ""
log_message "See $USER_HOME/AI_STACK_README.txt for detailed instructions"
log_message "Log file saved to: $INSTALL_LOG"

# Print summary
echo "================================================"
echo "INSTALLATION COMPLETE"
echo "================================================"
echo "Created scripts in $USER_HOME:"
echo "  • start_all.sh           - Start everything"
echo "  • start_openwebui.sh     - Start Open WebUI"
echo "  • verify_installation.sh - Check installation"
echo ""
echo "NEXT:"
echo "1. Log out and back in (or: newgrp docker)"
echo "2. Open LM Studio, download Mistral 7B model"
echo "3. Run: ./start_all.sh"
echo "================================================"