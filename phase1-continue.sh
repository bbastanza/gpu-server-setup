#!/usr/bin/env bash
# Phase 1 (continued): Run after ollama + qwen3:8b are installed.
# Picks up from where phase1-post-reboot.sh failed.
# Usage: ./phase1-continue.sh
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
step()  { echo -e "\n${GREEN}==>${NC} $1"; }
err()   { echo -e "${RED}[✗]${NC} $1"; }

pause() {
    echo ""
    read -rp "Press Enter to continue (or Ctrl+C to abort)..."
}

# ─── Context window ───
VRAM_MB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' ')
if [[ "$VRAM_MB" -ge 11000 ]]; then
    CTX=32768
    warn "Detected 12GB+ VRAM — using 32k context"
else
    CTX=16384
    warn "Detected <12GB VRAM — using 16k context"
fi

step "Step 6: Configuring context window (num_ctx=$CTX)"
warn "This launches ollama interactively. Run these commands:"
echo ""
echo "  /set parameter num_ctx $CTX"
echo "  /save qwen3:8b"
echo "  /bye"
echo ""
pause
ollama run qwen3:8b

# ─── Expose Ollama to LAN ───
step "Step 7: Exposing Ollama on 0.0.0.0:11434"
sudo mkdir -p /etc/systemd/system/ollama.service.d
cat <<'EOF' | sudo tee /etc/systemd/system/ollama.service.d/override.conf
[Service]
Environment="OLLAMA_HOST=0.0.0.0"
EOF
sudo systemctl daemon-reload
sudo systemctl restart ollama

sleep 2
if ss -tlnp | grep -q '0.0.0.0:11434'; then
    info "Ollama listening on 0.0.0.0:11434"
else
    err "Ollama not listening on 0.0.0.0 — check: sudo systemctl status ollama"
fi

# ─── Static IP ───
step "Step 8: Configuring static IP (10.0.0.1/24)"
ETH_IFACE=$(nmcli -t -f DEVICE,TYPE device | grep ethernet | head -1 | cut -d: -f1)
if [[ -z "$ETH_IFACE" ]]; then
    err "No ethernet interface found."
    exit 1
fi
info "Found ethernet interface: $ETH_IFACE"

ETH_CON=$(nmcli -t -f NAME,DEVICE con show | grep "$ETH_IFACE" | head -1 | cut -d: -f1)
if [[ -z "$ETH_CON" ]]; then
    sudo nmcli con add type ethernet con-name gpu-lan ifname "$ETH_IFACE" \
        ipv4.addresses 10.0.0.1/24 \
        ipv4.method manual
    ETH_CON="gpu-lan"
else
    sudo nmcli con mod "$ETH_CON" \
        ipv4.addresses 10.0.0.1/24 \
        ipv4.method manual \
        ipv4.gateway "" \
        ipv4.dns ""
fi

warn "Applying static IP — if you're on SSH, your session will drop."
warn "Reconnect with: ssh <user>@10.0.0.1"
pause
sudo nmcli con up "$ETH_CON"
info "Static IP 10.0.0.1/24 set on $ETH_IFACE"

# ─── Firewall ───
step "Step 9: Configuring firewall"
sudo firewall-cmd --zone=trusted --add-source=10.0.0.0/24 --permanent
sudo firewall-cmd --zone=public --add-service=ssh --permanent
sudo firewall-cmd --reload
info "Firewall: 10.0.0.0/24 trusted, SSH allowed"

# ─── Boot target ───
step "Step 10: Setting CLI boot target"
sudo systemctl set-default multi-user.target
info "Default boot target: multi-user.target"

# ─── GPU monitoring alias ───
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
echo "Test from laptop:"
echo "  ssh <user>@10.0.0.1"
echo "  curl http://10.0.0.1:11434/api/tags"
