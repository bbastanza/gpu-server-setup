#!/usr/bin/env bash
# Phase 1: GPU PC Setup Script for Fedora Server 43 (headless)
# Run as your sudo user, NOT as root.
# Usage: curl -O https://raw.githubusercontent.com/bbastanza/gpu-server-setup/main/phase1-setup.sh && chmod +x phase1-setup.sh && ./phase1-setup.sh
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

# ─── Step 1: Essentials ───
step "Step 1: Installing essentials"
sudo dnf install -y curl wget htop git
info "Essentials installed"

# ─── Step 2: SSH ───
step "Step 2: Enabling SSH"
sudo systemctl enable --now sshd
info "SSH enabled and running"

# ─── Step 3: NVIDIA Drivers ───
step "Step 3: Installing NVIDIA drivers via RPM Fusion"
warn "This installs RPM Fusion repos + akmod-nvidia + CUDA support"
pause

sudo dnf install -y \
  "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
  "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
info "RPM Fusion repos added"

sudo dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda
info "akmod-nvidia and CUDA installed"

warn "Building kernel module (2-5 min)... do NOT reboot yet"
sudo akmods --force
sudo dracut --force
info "Kernel module built"

warn "System needs to reboot now for NVIDIA drivers."
warn "After reboot, run this script again — it will detect the reboot and continue from Step 4."
echo ""
echo "  Verify after reboot: nvidia-smi"
echo "  If it fails: disable Secure Boot in BIOS, reboot again."
echo ""

# Leave a breadcrumb so we know to skip to step 4 on next run
touch ~/.phase1-rebooted

read -rp "Reboot now? [y/N] " yn
if [[ "$yn" =~ ^[Yy]$ ]]; then
    sudo reboot
else
    warn "Reboot manually when ready, then re-run this script."
    exit 0
fi
