#!/usr/bin/env bash
# Monthly update script for GPU PC.
# Usage: ./monthly-update.sh
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
err()   { echo -e "${RED}[✗]${NC} $1"; }

if ! ping -c 1 -W 3 google.com &>/dev/null; then
    err "No internet."
    exit 1
fi
info "Internet connected"

echo ""
warn "Starting monthly update — $(date '+%Y-%m-%d')"
echo ""

# System
sudo dnf upgrade -y --refresh
info "System packages updated"

# NVIDIA kernel module rebuild (in case kernel updated)
sudo akmods --force
sudo dracut --force
info "NVIDIA kernel module rebuilt"

# Ollama
curl -fsSL https://ollama.ai/install.sh | sh
info "Ollama updated"

# Update this repo
cd "$(dirname "$0")"
if git rev-parse --is-inside-work-tree &>/dev/null; then
    git pull
    info "gpu-server-setup repo updated"
fi

# Summary
echo ""
echo -e "${GREEN}════════════════════════════════${NC}"
echo -e "${GREEN} Update complete — $(date '+%Y-%m-%d')${NC}"
echo -e "${GREEN}════════════════════════════════${NC}"
echo ""
nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader
echo ""
echo "Models:"
ollama list
echo ""

if dnf needs-restarting -r &>/dev/null; then
    info "No reboot needed"
else
    warn "Reboot recommended (kernel or core libs updated)"
    read -rp "Reboot now? [y/N] " yn
    [[ "$yn" =~ ^[Yy]$ ]] && sudo reboot
fi
