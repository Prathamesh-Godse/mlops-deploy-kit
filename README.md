# Automation Framework — MLOps Deployment

> **Turn the entire deployment pipeline into a single command.**

---

## What This Is

Project 2 extends the MLOps stack from Project 1 with a Bash-based automation framework. Every manual step — installing Docker, building the image, configuring Nginx, enabling SSL — is captured in a script that reads from a single config file. No hardcoded values. No repeated commands. No chance of forgetting a step.

```bash
./scripts/deploy.sh config.yaml
```

That one line installs the system dependencies, builds and runs the Docker container, generates and enables the Nginx configuration, handles SSL, and runs a full end-to-end health check.

---

## Script Directory

```
scripts/
├── utils.sh     ← Sourced by all others. Logging, YAML parsing, helpers.
├── install.sh   ← Install Docker, Nginx, configure UFW
├── docker.sh    ← Build image, stop/remove old container, run new one
├── nginx.sh     ← Generate Nginx config, enable site, handle SSL, reload
└── deploy.sh    ← Orchestrator. Calls the three above in order.

config.yaml      ← All deployment variables. The only file you edit.
```

---

## The Config File

Every script reads `config.yaml`. Nothing is hardcoded inside the scripts themselves.

```yaml
domain: api.yourdomain.com
docker_image: digit-api
docker_container: digit-api
port: 8000
restart_policy: unless-stopped
app_dir: /home/ubuntu/digit-api
log_dir: /var/log/digit-api
nginx_config_name: digit-api
ssl_mode: cloudflare      # cloudflare | certbot
certbot_email: your@email.com
```

To deploy to a different domain or port: change one line. The scripts adapt.

---

## Usage

**Full deployment (fresh server):**
```bash
./scripts/deploy.sh config.yaml
```

**Re-deploy only (system already set up):**
```bash
./scripts/deploy.sh config.yaml --skip-install
```

**Run individual scripts:**
```bash
sudo ./scripts/install.sh config.yaml    # system setup only
./scripts/docker.sh config.yaml          # container only
sudo ./scripts/nginx.sh config.yaml      # Nginx only
```

---

## Documentation

| Document | Contents |
|---|---|
| [INDEX.md](INDEX.md) | Full table of contents |
| [01 · Overview](docs/01-overview/automation-overview.md) | Design decisions, script map, execution flow |
| [02 · Config Reference](docs/02-config/config-reference.md) | Every config.yaml key documented |
| [03 · utils.sh](docs/03-utils/utils-reference.md) | Shared utilities: logging, YAML parsing, helpers |
| [04 · install.sh](docs/04-install/install-script.md) | System installation walkthrough |
| [05 · docker.sh](docs/05-docker/docker-script.md) | Docker build and container lifecycle |
| [06 · nginx.sh](docs/06-nginx/nginx-script.md) | Nginx config generation and SSL |
| [07 · deploy.sh](docs/07-deploy/deploy-script.md) | Orchestrator and final health check |

---

*← [Project 1 — MLOps Documentation](../../README.md)*
