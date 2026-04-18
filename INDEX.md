# Index — Automation Framework Documentation

> Table of contents for Project 2: the Bash deployment automation stack.

---

## [01 · Automation Overview](docs/01-overview/automation-overview.md)
- Design principles: idempotency, config-driven, no hardcoding
- Script dependency map
- End-to-end execution flow
- What each phase does

---

## [02 · Config Reference](docs/02-config/config-reference.md)
- Every `config.yaml` key explained
- Valid values and defaults
- How the YAML parser works
- Customization examples

---

## [03 · utils.sh](docs/03-utils/utils-reference.md)
- How to source utils.sh
- Logging functions: `log_info`, `log_success`, `log_warn`, `log_error`, `log_step`
- `yaml_get` — config value extraction
- `require_commands` — dependency guard
- `require_root` — privilege check
- `wait_for_http` — polling health checker
- `handle_error` — ERR trap

---

## [04 · install.sh](docs/04-install/install-script.md)
- Idempotency: how already-installed components are detected and skipped
- Docker installation from official repository
- Docker group configuration
- Nginx installation
- UFW firewall rules

---

## [05 · docker.sh](docs/05-docker/docker-script.md)
- Reading Docker config from config.yaml
- Log directory preparation
- Stopping and removing an existing container
- Building the image with layer cache strategy
- Running the container (flags and their meanings)
- Health check polling

---

## [06 · nginx.sh](docs/06-nginx/nginx-script.md)
- Dynamic Nginx server block generation from config values
- Writing to `sites-available` and symlinking to `sites-enabled`
- SSL mode: `cloudflare` — certificate validation
- SSL mode: `certbot` — automated certificate acquisition
- `nginx -t` and reload

---

## [07 · deploy.sh](docs/07-deploy/deploy-script.md)
- Argument parsing (`--skip-install` flag)
- Log bootstrapping before `utils.sh` is sourced
- Phase 1 → 2 → 3 orchestration with privilege escalation
- End-to-end health check (internal + public)
- Deployment summary output

---

## File Reference

| File | Description |
|---|---|
| `config.yaml` | Deployment configuration |
| `scripts/utils.sh` | Shared logging and helper functions |
| `scripts/install.sh` | System dependencies setup |
| `scripts/docker.sh` | Docker image and container management |
| `scripts/nginx.sh` | Nginx reverse proxy and SSL |
| `scripts/deploy.sh` | One-command orchestrator |

---

*← [README](README.md) | [Project 1 Index](../../INDEX.md)*
