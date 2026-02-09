# Local AI Inference Server + Multi-Model OpenCode Setup

## Current Status
- **Phase 1**: IN PROGRESS — Fedora Server installed on GPU PC, running dnf updates
- **Phase 2**: NOT STARTED — Physical networking (switch connected, IPs not configured yet)
- **Phase 3**: NOT STARTED — OpenCode installation
- **Phase 4**: NOT STARTED — Agent configuration
- **Phase 5**: NOT STARTED — Verification

## Hardware

| Machine | Role | OS | Specs |
|---------|------|----|-------|
| Desktop PC | Headless LLM inference server | Fedora Server 43 (minimal, no DE) | Ryzen 5 3600, RTX 2060 6GB (upgrading to RTX 3060 12GB), 32GB DDR4, B450 |
| Laptop | Primary dev machine | openSUSE Tumbleweed | Runs OpenCode/Claude Code, editor, project files |
| Orange Pi | Secondary dev machine | Ubuntu Desktop (ARM) | Lighter work |
| Network switch | Private LAN | — | Unmanaged gigabit Ethernet, already owned |

## Network Topology

```
Private LAN: 10.0.0.0/24 (Ethernet, no internet)
Internet:    WiFi on each machine independently

GPU PC:    10.0.0.1 (Ethernet)
Laptop:    10.0.0.2 (Ethernet)
Orange Pi: 10.0.0.3 (Ethernet)
```

## Phase 1: Fedora GPU PC Setup

### Completed
- [x] Fedora Server 43 installed (minimal, no DE)
- [x] dnf update running

### Remaining
- [ ] Install essentials: `curl wget htop git`
- [ ] Enable SSH: `sudo systemctl enable --now sshd`
- [ ] Install NVIDIA drivers via RPM Fusion:
  ```bash
  sudo dnf install -y \
    https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
    https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
  sudo dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda
  sudo akmods --force && sudo dracut --force && sudo reboot
  # Verify: nvidia-smi
  ```
- [ ] Install Ollama:
  ```bash
  curl -fsSL https://ollama.ai/install.sh | sh
  sudo systemctl enable ollama
  ```
- [ ] Pull models:
  ```bash
  ollama pull qwen3:8b
  # RTX 3060 only: ollama pull qwen3-coder-next
  ```
- [ ] Configure context windows:
  ```bash
  ollama run qwen3:8b
  >>> /set parameter num_ctx 16384   # RTX 2060 (6GB)
  # or num_ctx 32768 for RTX 3060 (12GB)
  >>> /save qwen3:8b
  >>> /bye
  ```
- [ ] Expose Ollama to LAN:
  ```bash
  sudo systemctl edit ollama
  # Add:
  # [Service]
  # Environment="OLLAMA_HOST=0.0.0.0"
  sudo systemctl daemon-reload && sudo systemctl restart ollama
  # Verify: ss -tlnp | grep 11434 shows 0.0.0.0
  ```
- [ ] Configure static IP 10.0.0.1/24 on Ethernet (no gateway, no DNS)
- [ ] Firewall: allow 10.0.0.0/24 to port 11434, allow SSH
- [ ] Set boot target: `sudo systemctl set-default multi-user.target`
- [ ] GPU monitoring alias: `alias gpuwatch="watch -n 1 nvidia-smi"`

## Phase 2: Physical Networking

- [ ] All machines cabled to switch
- [ ] Laptop: static IP 10.0.0.2/24 on Ethernet (nmcli, no gateway)
- [ ] Orange Pi: static IP 10.0.0.3/24 on Ethernet
- [ ] Ping test: all machines reach each other on 10.0.0.x
- [ ] `curl http://10.0.0.1:11434/api/tags` from laptop and Orange Pi
- [ ] Test inference over network

## Phase 3: OpenCode Installation

- [ ] Install OpenCode on laptop and Orange Pi
- [ ] Create `~/.config/opencode/opencode.json` pointing to `http://10.0.0.1:11434/v1`
- [ ] Add Anthropic/OpenAI API keys
- [ ] Test local model + cloud model from OpenCode

### opencode.json template
```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "ollama": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "GPU PC (remote Ollama)",
      "options": { "baseURL": "http://10.0.0.1:11434/v1" },
      "models": {
        "qwen3:8b": {
          "name": "Qwen3 8B (remote GPU)",
          "limit": { "context": 16384, "output": 4096 }
        }
      }
    },
    "anthropic": {},
    "openai": {}
  },
  "model": "anthropic/claude-sonnet-4-5-20250929"
}
```

## Phase 4: Agent Configuration

- [ ] Create explorer subagent (local model, read-only codebase search)
- [ ] Create reviewer subagent (local model, code review)
- [ ] Verify agents route to remote Ollama

## Phase 5: Verification & Reboot Test

- [ ] Full connectivity check
- [ ] Inference works from all clients
- [ ] Everything survives GPU PC reboot
- [ ] Cloud + local model switching works in OpenCode

## Troubleshooting Quick Reference

| Problem | Fix |
|---------|-----|
| `nvidia-smi` not found | `sudo akmods --force && sudo dracut --force && reboot`. Disable Secure Boot if needed. |
| `curl: connection refused` to 11434 | Check `OLLAMA_HOST=0.0.0.0` in systemd override, restart ollama |
| OOM / slow models | Reduce `num_ctx`. 2060: 8192-16384. 3060: 32768 |
| No route to host | Check cables, switch, static IPs with `ip addr show` |
| WiFi broken after static Ethernet | Remove gateway from Ethernet: `nmcli con mod "name" ipv4.gateway ""` |
| firewalld blocking | `sudo firewall-cmd --zone=trusted --list-sources` should include 10.0.0.0/24 |
| SELinux blocking | `sudo ausearch -m avc -ts recent`, `sudo setenforce 0` to test |

## Key Decisions
- Fedora Server 43 (minimal) for GPU PC
- Private 10.0.0.0/24 LAN, no router, WiFi for internet
- Ollama for local inference, Qwen3:8B as primary local model
- Cloud APIs (Anthropic/OpenAI) for complex tasks via WiFi
- OpenCode as the coding agent interface
