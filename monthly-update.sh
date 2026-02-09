#!/usr/bin/env bash
# Monthly update script for GPU PC.
# Expects temporary internet access (USB tether, WiFi dongle, or router ethernet).
# Usage: ./monthly-update.sh
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
err()   { echo -e "${RED}[✗]${NC} $1"; }

# Check internet
if ! ping -c 1 -W 3 google.com &>/dev/null; then
    err "No internet. Connect to a network first (USB tether, WiFi, or router ethernet)."
    exit 1
fi
info "Internet connected"

echo ""
warn "Starting monthly update — $(date '+%Y-%m-%d')"
echo ""

# System update
sudo dnf upgrade -y --refresh
info "System packages updated"

# Rebuild NVIDIA module if kernel was updated
sudo akmods --force
sudo dracut --force
info "NVIDIA kernel module rebuilt"

# Update Ollama
curl -fsSL https://ollama.ai/install.sh | sh
info "Ollama updated"

# Show summary
echo ""
echo -e "${GREEN}════════════════════════════════${NC}"
echo -e "${GREEN} Update complete — $(date '+%Y-%m-%d')${NC}"
echo -e "${GREEN}════════════════════════════════${NC}"
echo ""
echo "Models installed:"
ollama list
echo ""

if dnf needs-restarting -r &>/dev/null; then
    info "No reboot needed"
else
    warn "Reboot recommended (kernel or core libs updated)"
    read -rp "Reboot now? [y/N] " yn
    [[ "$yn" =~ ^[Yy]$ ]] && sudo reboot
fi
