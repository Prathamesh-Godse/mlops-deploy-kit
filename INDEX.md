# Index — MLOps Deploy Kit

> Navigation reference for the Bash deployment automation framework.

---

## Quick Reference

| File | Description |
|---|---|
| [README.md](README.md) | Project overview, config template, usage |
| [scripts/utils.sh](scripts/utils.sh) | Shared logging and helper functions |
| [scripts/install.sh](scripts/install.sh) | System dependencies setup |
| [scripts/docker.sh](scripts/docker.sh) | Docker image and container management |
| [scripts/nginx.sh](scripts/nginx.sh) | Nginx reverse proxy and SSL |
| [scripts/deploy.sh](scripts/deploy.sh) | One-command orchestrator |
| [LICENSE](LICENSE) | MIT License |

---

## utils.sh

- How to source `utils.sh` from other scripts
- Logging functions: `log_info`, `log_success`, `log_warn`, `log_error`, `log_step`
- `yaml_get` — config value extraction
- `require_commands` — dependency guard
- `require_root` — privilege check
- `wait_for_http` — polling health checker
- `handle_error` — ERR trap

---

## install.sh

- Idempotency: how already-installed components are detected and skipped
- Docker installation from official repository
- Docker group configuration
- Nginx installation
- UFW firewall rules

---

## docker.sh

- Reading Docker config from `config.yaml`
- Log directory preparation
- Stopping and removing an existing container
- Building the image with layer cache strategy
- Running the container (flags and their meanings)
- Health check polling

---

## nginx.sh

- Dynamic Nginx server block generation from config values
- Writing to `sites-available` and symlinking to `sites-enabled`
- SSL mode: `cloudflare` — certificate path validation
- SSL mode: `certbot` — automated certificate acquisition
- `nginx -t` and reload

---

## deploy.sh

- Argument parsing (`--skip-install` flag)
- Log bootstrapping before `utils.sh` is sourced
- Phase 1 → 2 → 3 orchestration with privilege escalation
- End-to-end health check (internal + public)
- Deployment summary output

---

*[← README](README.md)*
