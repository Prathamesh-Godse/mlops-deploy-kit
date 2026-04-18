# 01 · Automation Overview

*← [Index](../../INDEX.md)*

---

## The Problem This Solves

Project 1 produced a documented deployment process — a set of steps a human reads and executes. That works once. It fails to scale when:

- The server needs to be rebuilt (hardware failure, migration)
- A model update needs re-deploying at 2am
- A new team member needs to replicate the environment
- The deployment needs to be tested on a staging server first

Manual steps have a worse problem: they accumulate invisible state. After six weeks, no one is sure whether that one `sudo ufw` command was run with the right flags. The documentation may have drifted from reality.

This automation framework eliminates that class of failure. The scripts are the source of truth. The config file is the only variable.

---

## Design Principles

**1. Config-driven, not hardcoded.**
No domain name, port, image name, or file path appears inside a script. Everything is read from `config.yaml`. Changing the deployment target means editing one file — not hunting through four scripts.

**2. Idempotent by default.**
Every script checks the current state before acting. If Docker is already installed, it skips the installation. If the container already exists, it stops and removes it before re-running. Running `deploy.sh` twice on the same server is safe.

**3. One-command execution.**
The full deployment — from bare Ubuntu to a live HTTPS API — runs with:
```bash
./scripts/deploy.sh config.yaml
```
No intermediate commands. No manual "wait for this to finish before the next step."

**4. Fail loudly and early.**
`set -euo pipefail` is set in every script. Any unhandled error stops execution immediately. The `handle_error` trap in `utils.sh` reports the exact line number that failed and writes it to the log. Deployments never silently half-complete.

**5. Audit trail.**
Every log function writes to both the terminal and a persistent log file (`deploy.log`). If something went wrong during an unattended run, the log file tells you exactly what happened and when.

---

## Script Dependency Map

```
deploy.sh
    │
    ├── sources: utils.sh          ← first thing loaded
    │
    ├── calls: install.sh          ← Phase 1 (sudo)
    │           └── sources: utils.sh
    │
    ├── calls: docker.sh           ← Phase 2
    │           └── sources: utils.sh
    │
    └── calls: nginx.sh            ← Phase 3 (sudo)
                └── sources: utils.sh
```

`utils.sh` is never executed directly. It is sourced by every other script, providing shared functions without duplication.

The three worker scripts (`install.sh`, `docker.sh`, `nginx.sh`) can also be run independently. This is useful when only one part of the stack needs to change — for example, updating the Nginx config without touching Docker.

---

## Execution Flow

```
./scripts/deploy.sh config.yaml
│
│  ── Pre-flight ──────────────────────────────────────────
│  1. Validate config.yaml exists
│  2. Bootstrap log directory (raw grep, before utils.sh loads)
│  3. Source utils.sh
│  4. Read and display config values
│
│  ── Phase 1: System Installation ────────────────────────
│  5. sudo install.sh config.yaml
│     ├─ apt-get update
│     ├─ Install Docker (from official repo, with GPG key)
│     ├─ Add user to docker group
│     ├─ Install Nginx
│     └─ Configure UFW (OpenSSH + Nginx Full; block 8000)
│
│  ── Phase 2: Docker Deployment ──────────────────────────
│  6. docker.sh config.yaml
│     ├─ Create log directory on host
│     ├─ Stop + remove existing container (if any)
│     ├─ docker build -t <image> .
│     ├─ docker run -d --name <container> -p <port>:<port>
│     │             --restart <policy> -v <log_dir>:/app/logs
│     └─ Health check: GET http://localhost:<port>/
│
│  ── Phase 3: Nginx + SSL ────────────────────────────────
│  7. sudo nginx.sh config.yaml
│     ├─ Generate server block from config values
│     ├─ Write to /etc/nginx/sites-available/<name>
│     ├─ Symlink to sites-enabled/
│     ├─ SSL:
│     │   cloudflare: validate cert/key paths
│     │   certbot:    run certbot --nginx
│     ├─ nginx -t
│     └─ systemctl reload nginx
│
│  ── Final health check ──────────────────────────────────
│  8. GET http://localhost:<port>/     (internal)
│  9. GET https://<domain>/           (public)
│
│  ── Summary ─────────────────────────────────────────────
│ 10. Print URLs, container name, log path, elapsed time
```

---

## What `--skip-install` Does

```bash
./scripts/deploy.sh config.yaml --skip-install
```

This skips Phase 1 entirely. Useful for:

- **Re-deploying after a code/model change** — Docker and Nginx are already there; just rebuild the image and restart the container.
- **Repeated testing** — running the full install every time adds 2–3 minutes of apt operations. `--skip-install` gets to the actual application deployment in seconds.

When `--skip-install` is set, `deploy.sh` verifies that `docker`, `nginx`, and `curl` are already available before proceeding. If any are missing, it exits with an error and suggests running without the flag.

---

## Privilege Model

| Script | Needs root? | Why |
|---|---|---|
| `utils.sh` | No | Helper functions only |
| `install.sh` | Yes | `apt-get`, `systemctl`, `ufw`, `usermod` |
| `docker.sh` | No (with docker group) | `docker` commands |
| `nginx.sh` | Yes | `/etc/nginx/`, `systemctl reload nginx`, `certbot` |
| `deploy.sh` | No (escalates internally) | Calls `sudo` for install.sh and nginx.sh |

`deploy.sh` does not need to be run as root. It escalates with `sudo` only for the two scripts that require it. If already running as root (e.g., in a CI pipeline), it calls the scripts directly.

---

*→ Next: [02 · Config Reference](../02-config/config-reference.md)*
