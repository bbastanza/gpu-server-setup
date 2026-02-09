#!/usr/bin/env bash
# Phase 1 (continued): Run AFTER reboot, once nvidia-smi works.
# Usage: ./phase1-post-reboot.sh
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
step()  { echo -e "\n${GREEN}==>${NC} $1"; }
err()   { echo -e "${RED}[✗]${NC} $1"; }

pause() {
    echo ""
    read -rp "Press Enter to continue (or Ctrl+C to abort)..."
}

# ─── Verify NVIDIA ───
step "Verifying NVIDIA driver"
if ! command -v nvidia-smi &>/dev/null; then
    err "nvidia-smi not found. Driver may not have loaded."
    err "Try: sudo akmods --force && sudo dracut --force && sudo reboot"
    err "If Secure Boot is on, disable it in BIOS."
    exit 1
fi
nvidia-smi
info "NVIDIA driver working"
pause

# ─── Step 4: Ollama ───
step "Step 4: Installing Ollama"
curl -fsSL https://ollama.ai/install.sh | sh
sudo systemctl enable ollama
info "Ollama installed and enabled on boot"

# ─── Step 5: Pull model ───
step "Step 5: Pulling Qwen3:8B"
ollama pull qwen3:8b
info "Qwen3:8B pulled"

# Check VRAM to decide context size
VRAM_MB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' ')
if [[ "$VRAM_MB" -ge 11000 ]]; then
    GPU_TIER="3060"
    CTX=32768
    warn "Detected 12GB+ VRAM — using 32k context"
    echo ""
    read -rp "Also pull qwen3-coder-next? (large model, 3060+ only) [y/N] " yn
    if [[ "$yn" =~ ^[Yy]$ ]]; then
        ollama pull qwen3-coder-next
        info "Qwen3-Coder-Next pulled"
    fi
else
    GPU_TIER="2060"
    CTX=16384
    warn "Detected <12GB VRAM — using 16k context"
fi

# ─── Step 6: Configure context window ───
step "Step 6: Configuring context window (num_ctx=$CTX)"
warn "This launches ollama interactively. Run these commands:"
echo ""
echo "  /set parameter num_ctx $CTX"
echo "  /save qwen3:8b"
echo "  /bye"
echo ""
pause
ollama run qwen3:8b

# ─── Step 7: Expose Ollama to LAN ───
step "Step 7: Exposing Ollama on 0.0.0.0:11434"
sudo mkdir -p /etc/systemd/system/ollama.service.d
cat <<'EOF' | sudo tee /etc/systemd/system/ollama.service.d/override.conf
[Service]
Environment="OLLAMA_HOST=0.0.0.0"
EOF
sudo systemctl daemon-reload
sudo systemctl restart ollama

# Verify
sleep 2
if ss -tlnp | grep -q '0.0.0.0:11434'; then
    info "Ollama listening on 0.0.0.0:11434"
else
    err "Ollama not listening on 0.0.0.0 — check: sudo systemctl status ollama"
fi

# ─── Step 8: Static IP ───
step "Step 8: Configuring static IP (10.0.0.1/24)"
echo "Current network devices:"
nmcli device status
echo ""

# Find ethernet interface
ETH_IFACE=$(nmcli -t -f DEVICE,TYPE device | grep ethernet | head -1 | cut -d: -f1)
if [[ -z "$ETH_IFACE" ]]; then
    err "No ethernet interface found. Configure manually."
    exit 1
fi
info "Found ethernet interface: $ETH_IFACE"

# Find or create connection
ETH_CON=$(nmcli -t -f NAME,DEVICE con show | grep "$ETH_IFACE" | head -1 | cut -d: -f1)
if [[ -z "$ETH_CON" ]]; then
    warn "No existing connection for $ETH_IFACE — creating one"
    sudo nmcli con add type ethernet con-name gpu-lan ifname "$ETH_IFACE" \
        ipv4.addresses 10.0.0.1/24 \
        ipv4.method manual
    ETH_CON="gpu-lan"
else
    info "Using existing connection: $ETH_CON"
    sudo nmcli con mod "$ETH_CON" \
        ipv4.addresses 10.0.0.1/24 \
        ipv4.method manual \
        ipv4.gateway "" \
        ipv4.dns ""
fi
sudo nmcli con up "$ETH_CON"
info "Static IP 10.0.0.1/24 set on $ETH_IFACE"

# ─── Step 9: Firewall ───
step "Step 9: Configuring firewall"
sudo firewall-cmd --zone=trusted --add-source=10.0.0.0/24 --permanent
sudo firewall-cmd --zone=public --add-service=ssh --permanent
sudo firewall-cmd --reload
info "Firewall: 10.0.0.0/24 trusted, SSH allowed"

# ─── Step 10: Boot target ───
step "Step 10: Setting CLI boot target"
sudo systemctl set-default multi-user.target
info "Default boot target: multi-user.target"

# ─── Step 11: GPU monitoring alias ───
step "Step 11: Adding gpuwatch alias"
if ! grep -q 'alias gpuwatch' ~/.bashrc 2>/dev/null; then
    echo 'alias gpuwatch="watch -n 1 nvidia-smi"' >> ~/.bashrc
fi
info "gpuwatch alias added to .bashrc"

# ─── Done ───
echo ""
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN} Phase 1 Complete!${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo ""
echo "Summary:"
echo "  GPU:      $(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null)"
echo "  VRAM:     ${VRAM_MB}MB"
echo "  Ollama:   listening on 0.0.0.0:11434"
echo "  Model:    qwen3:8b (ctx=$CTX)"
echo "  IP:       10.0.0.1/24 on $ETH_IFACE"
echo "  SSH:      enabled"
echo "  Firewall: 10.0.0.0/24 trusted"
echo ""
echo "Next: Connect the switch, configure laptop (10.0.0.2) and"
echo "Orange Pi (10.0.0.3), then test with:"
echo "  curl http://10.0.0.1:11434/api/tags"
