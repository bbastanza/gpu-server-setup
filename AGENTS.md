# AGENTS.md — GPU PC Ollama Setup

## Project Overview
Infrastructure-as-code repo for setting up a headless Fedora Server 43 GPU PC (RTX 2060/3060) as a local AI inference server using Ollama, connected to OpenCode clients over private LAN.

**Tech Stack:** Bash, systemd, NetworkManager, firewalld, Ollama, NVIDIA drivers

---

## Build/Test Commands

### Testing Scripts (Dry Run)
```bash
# Validate syntax
bash -n phase1-setup.sh
bash -n phase1-post-reboot.sh
bash -n phase1-continue.sh
bash -n upgrade-script.sh

# ShellCheck (if installed)
shellcheck phase1-*.sh upgrade-script.sh
```

### Running Scripts
```bash
# Phase 1 initial setup (pre-reboot)
./phase1-setup.sh

# Phase 1 post-reboot (full setup)
./phase1-post-reboot.sh

# Phase 1 continuation (if model pull failed)
./phase1-continue.sh

# Monthly maintenance
./upgrade-script.sh
```

### Testing Ollama
```bash
# Check service
systemctl status ollama

# List models
curl http://10.0.0.1:11434/api/tags

# Test inference
curl -X POST http://10.0.0.1:11434/api/generate \
  -d '{"model":"qwen3:8b","prompt":"Hello","stream":false}' | jq

# Test from remote client
ssh user@10.0.0.1 'ollama list'
```

### Network Testing
```bash
# Check static IP
ip addr show enp34s0

# Test connectivity from laptop (10.0.0.2)
ping -c 3 10.0.0.1
curl http://10.0.0.1:11434/api/tags

# Check firewall
sudo firewall-cmd --zone=trusted --list-sources
sudo firewall-cmd --list-services
```

### GPU Monitoring
```bash
# Watch GPU usage
gpuwatch  # alias for: watch -n 1 nvidia-smi

# Check VRAM
nvidia-smi --query-gpu=memory.total,memory.used --format=csv

# Driver info
nvidia-smi --query-gpu=driver_version --format=csv,noheader
```

---

## Code Style Guidelines

### Bash Scripts

#### Shebang & Options
```bash
#!/usr/bin/env bash
set -euo pipefail  # Exit on error, unset vars, pipe failures
```

#### Color Output
```bash
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
err()   { echo -e "${RED}[✗]${NC} $1"; }
step()  { echo -e "\n${GREEN}==>${NC} $1"; }
```

#### Error Handling
- Check command existence: `command -v nvidia-smi &>/dev/null`
- Verify operations: `if ss -tlnp | grep -q '0.0.0.0:11434'; then`
- Exit on critical failures: `exit 1`
- Use `pause()` for user confirmation before dangerous ops

#### Variables
- Uppercase for constants: `CTX=16384`, `VRAM_MB`, `ETH_IFACE`
- Detect hardware dynamically (don't hardcode)
- Quote variables: `"$ETH_IFACE"`, not `$ETH_IFACE`

#### Naming Conventions
- Script names: `phase1-setup.sh`, `upgrade-script.sh` (kebab-case)
- Functions: `info()`, `pause()`, `step()` (lowercase, descriptive)
- Variables: `VRAM_MB`, `ETH_CON`, `GPU_TIER` (SCREAMING_SNAKE_CASE)

#### NetworkManager Commands
```bash
# Find interface
nmcli -t -f DEVICE,TYPE device | grep ethernet

# Create connection
sudo nmcli con add type ethernet con-name gpu-lan ifname "$IFACE" \
  ipv4.addresses 10.0.0.1/24 \
  ipv4.method manual

# Modify connection (remove gateway for non-internet connection)
sudo nmcli con mod "$CON" ipv4.gateway "" ipv4.dns ""

# Apply
sudo nmcli con up "$CON"
```

#### Systemd Overrides
```bash
# Create override directory
sudo mkdir -p /etc/systemd/system/ollama.service.d

# Write override file
cat <<'EOF' | sudo tee /etc/systemd/system/ollama.service.d/override.conf
[Service]
Environment="OLLAMA_HOST=0.0.0.0"
EOF

# Reload and restart
sudo systemctl daemon-reload
sudo systemctl restart ollama
```

#### Output Clarity
- Use `step()` to mark major sections
- Use `info()` for success, `warn()` for caution, `err()` for failures
- Echo instructions clearly before interactive commands
- Show summary at end (GPU model, IP, services)

---

## Configuration Management

### Ollama Configuration
```bash
# Context window (interactive)
ollama run qwen3:8b
/set parameter num_ctx 16384
/save qwen3:8b
/bye

# Verify settings
curl http://10.0.0.1:11434/api/show -d '{"name":"qwen3:8b"}' | jq
```

### OpenCode Configuration
Location: `~/.config/opencode/opencode.json`

```json
{
  "provider": {
    "ollama": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "GPU PC Ollama",
      "options": { "baseURL": "http://10.0.0.1:11434/v1" },
      "models": {
        "qwen3:8b": {
          "name": "Qwen3 8B (GPU PC)",
          "limit": { "context": 16384, "output": 4096 }
        },
        "qwen2.5:7b": {
          "name": "Qwen2.5 7B (GPU PC)",
          "limit": { "context": 16384, "output": 4096 }
        }
      }
    }
  }
}
```

### Agent Configuration
Location: `~/.config/opencode/agents/*.md`

Front matter format:
```yaml
---
description: Brief description
mode: subagent
model: ollama/qwen2.5:7b
temperature: 0.1
permission:
  read: allow
  glob: allow
  grep: allow
  bash: deny
  edit: deny
  write: deny
---
```

---

## Common Patterns

### VRAM-Based Decisions
```bash
VRAM_MB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1 | tr -d ' ')
if [[ "$VRAM_MB" -ge 11000 ]]; then
    CTX=32768  # 3060 12GB
else
    CTX=16384  # 2060 6GB
fi
```

### Interface Detection
```bash
ETH_IFACE=$(nmcli -t -f DEVICE,TYPE device | grep ethernet | head -1 | cut -d: -f1)
if [[ -z "$ETH_IFACE" ]]; then
    err "No ethernet interface found"
    exit 1
fi
```

### Internet Connectivity Check
```bash
if ! ping -c 1 -W 3 google.com &>/dev/null; then
    err "No internet."
    exit 1
fi
```

---

## Troubleshooting

### Script Failures
- Check logs: `journalctl -xe`
- Verify syntax: `bash -n script.sh`
- Run with debug: `bash -x script.sh`

### Ollama Issues
- Service status: `systemctl status ollama`
- Listening port: `ss -tlnp | grep 11434`
- Logs: `journalctl -u ollama -f`

### Network Issues
- IP config: `ip addr show`
- Routes: `ip route`
- Firewall: `sudo firewall-cmd --list-all`
- Test API: `curl http://10.0.0.1:11434/api/tags`

### NVIDIA Driver Issues
- Rebuild module: `sudo akmods --force && sudo dracut --force && reboot`
- Check Secure Boot: Must be disabled for unsigned kernel modules
- Verify load: `lsmod | grep nvidia`

---

## Project Structure
```
.
├── CLAUDE.md              # Project state/decisions (primary doc)
├── AGENTS.md              # This file (agent guidelines)
├── phase1-setup.sh        # Pre-reboot setup script
├── phase1-post-reboot.sh  # Post-reboot full setup
├── phase1-continue.sh     # Continuation script (if post-reboot fails)
├── upgrade-script.sh      # Monthly maintenance script
└── .git/                  # Git repo
```

---

## Key Facts for Agents

1. **No tests** — this is infra setup, validation is manual
2. **Destructive operations** — scripts modify systemd, NetworkManager, firewalld
3. **Requires sudo** — all scripts need elevated privileges
4. **Interactive prompts** — use `pause()` before risky operations
5. **Hardware detection** — scripts adapt to RTX 2060 vs 3060 automatically
6. **Private LAN only** — 10.0.0.0/24, no gateway/DNS on ethernet
7. **WiFi for internet** — GPU PC keeps WiFi enabled for dnf updates
8. **Idempotent where possible** — scripts check before creating (e.g., connection exists)

When making changes:
- Preserve error handling (`set -euo pipefail`)
- Keep output colorized and clear
- Detect hardware/config dynamically
- Test on both RTX 2060 and 3060 scenarios (or detect)
- Update CLAUDE.md when changing architecture/decisions
