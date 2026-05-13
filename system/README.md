# System Reference Configs

These are **reference copies** of host-level configuration files. They are NOT deployed from this repository.

To install or update these configs, copy them manually to the appropriate system paths and reload the relevant services.

## Systemd Services

| File | System Path | Description |
|------|-------------|-------------|
| `systemd/ollama.service` | `/etc/systemd/system/ollama.service` | Ollama server pinned to NVIDIA RTX 3090 (port 11434) |
| `systemd/ollama-amd.service` | `/etc/systemd/system/ollama-amd.service` | Ollama server pinned to AMD W7800 (port 11435) |
| `systemd/nvidia-cdi-refresh.service` | `/etc/systemd/system/nvidia-cdi-refresh.service` | NVIDIA CDI spec refresh for container runtime |

After modifying systemd files:
```bash
sudo systemctl daemon-reload
sudo systemctl restart ollama
sudo systemctl restart ollama-amd
```

## Docker

| File | System Path | Description |
|------|-------------|-------------|
| `docker/daemon.json` | `/etc/docker/daemon.json` | Docker daemon config with NVIDIA runtime |

After modifying:
```bash
sudo systemctl restart docker
```
