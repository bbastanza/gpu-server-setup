# Local AI Inference Server + Multi-Model OpenCode Setup

## Current Status
- **Phase 1**: ✅ COMPLETE — All systems operational on GPU PC
- **Phase 2**: MOSTLY COMPLETE — GPU PC & laptop connected, verified. Orange Pi remains
- **Phase 3**: NOT STARTED — OpenCode installation
- **Phase 4**: NOT STARTED — Agent configuration
- **Phase 5**: NOT STARTED — Verification

## Hardware

| Machine | Role | OS | Specs |
|---------|------|----|-------|
| Desktop PC | Headless LLM inference server | Fedora Server 43 (minimal, no DE) | Ryzen 5 3600, RTX 2060 6GB (upgrading to RTX 3060 12GB), 32GB DDR4, B450 |
| Laptop | Primary dev machine | openSUSE Tumbleweed | Runs OpenCode/Claude Code, editor, project files |
| Orange Pi | Secondary dev machine | Ubuntu Desktop (ARM) | Lighter work |
| Network switch | Private LAN | — | Unmanaged gigabit Ethernet, 5-port (port 5 is uplink, don't use) |

## Network Topology

```
Private LAN: 10.0.0.0/24 (Ethernet, no internet)
Internet:    WiFi on each machine independently

GPU PC:    10.0.0.1 (Ethernet - enp34s0 = onboard NIC)
Laptop:    10.0.0.2 (Ethernet - enp0s20f0u1u2u4 = KVM USB adapter)
Orange Pi: 10.0.0.3 (Ethernet - TBD)

Switch ports: 1=GPU PC, 2=Laptop, 3=Orange Pi (when ready)

Note: Laptop shares KVM ethernet w/ GPU PC. KVM switch determines which machine sees it. LAN access only when KVM on laptop side.
```

## Phase 1: Fedora GPU PC Setup

### ✅ All Complete
- [x] Fedora Server 43 installed (minimal, no DE)
- [x] System updated (`dnf update`)
- [x] Essentials installed (curl, wget, htop, git)
- [x] SSH enabled and running
- [x] NVIDIA drivers installed via RPM Fusion (akmod-nvidia)
- [x] nvidia-smi working (RTX 2060)
- [x] Ollama installed and enabled on boot
- [x] Qwen3:8B model pulled
- [x] Context window configured (num_ctx 16384, saved)
- [x] Ollama exposed on 0.0.0.0:11434 (systemd override created)
- [x] Static IP: 10.0.0.1/24 on enp34s0 (onboard NIC, gpu-lan connection)
- [x] Firewall: 10.0.0.0/24 trusted, SSH allowed
- [x] Boot target: multi-user.target
- [x] gpuwatch alias added

## Phase 2: Physical Networking

### ✅ Completed
- [x] GPU PC connected to switch port 1
- [x] Laptop connected to switch port 2 (via KVM USB ethernet)
- [x] Laptop static IP set: 10.0.0.2/24 on enp0s20f0u1u2u4
- [x] Ping test successful (0.22ms avg)
- [x] Ollama API accessible from laptop (`curl http://10.0.0.1:11434/api/tags` works)

### Remaining
- [ ] Orange Pi: connect to port 3, set 10.0.0.3/24
- [ ] Full inference test over network

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

## Known Issues
- Laptop uses KVM's USB ethernet (enp0s20f0u1u2u4). Can't access LAN when KVM switched to GPU PC. Consider dedicated USB adapter for laptop if simultaneous access needed.
- GPU PC has both onboard NIC (enp34s0) and USB ethernet (enp3s0f0u2u2u4). Only onboard NIC used for LAN.

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
| Static IP on wrong interface | Check `nmcli device status`, use `enp34s0` (onboard), not USB adapter |

## Key Decisions
- Fedora Server 43 (minimal) for GPU PC
- Private 10.0.0.0/24 LAN, no router, WiFi for internet
- Ollama for local inference, Qwen3:8B as primary local model
- Cloud APIs (Anthropic/OpenAI) for complex tasks via WiFi
- OpenCode as the coding agent interface
- WiFi stays on GPU PC for updates (upgrade-script.sh)

## Scripts
- `phase1-setup.sh` — pre-reboot: essentials, SSH, NVIDIA drivers
- `phase1-post-reboot.sh` — full post-reboot setup (may fail at model pull)
- `phase1-continue.sh` — picks up after model pull (context, ollama expose, IP, firewall)
- `upgrade-script.sh` — monthly: dnf upgrade, nvidia rebuild, ollama update, git pull
