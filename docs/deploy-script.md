# 07 · deploy.sh

*← [Index](../../INDEX.md) · [nginx.sh](../06-nginx/nginx-script.md)*

---

## Purpose

`deploy.sh` is the single entry point for the entire deployment pipeline. It orchestrates the three worker scripts in the correct order, handles privilege escalation, bootstraps logging before any other script runs, performs a final end-to-end health check, and prints a human-readable deployment summary.

This is the only script an operator needs to remember.

---

## Usage

```bash
# Full deployment — fresh server
./scripts/deploy.sh config.yaml

# Re-deploy only — system already configured
./scripts/deploy.sh config.yaml --skip-install
```

Does not need to be run as root. It escalates internally with `sudo` for the two scripts that require it (`install.sh` and `nginx.sh`).

---

## Argument Parsing

```bash
CONFIG_FILE="$1"
SKIP_INSTALL=false

if [[ "${2:-}" == "--skip-install" ]]; then
    SKIP_INSTALL=true
fi
```

`"${2:-}"` uses Bash parameter expansion with a default of empty string. This prevents `set -u` from throwing "unbound variable" if `$2` is not provided.

If any argument other than `--skip-install` is passed as `$2`, it is silently ignored. This is intentional — the script favors simplicity over exhaustive argument validation for a two-flag interface.

---

## Log Bootstrapping

This is the most subtle part of `deploy.sh`. `utils.sh` provides all logging functions, but `utils.sh` itself needs `$DEPLOY_LOG` to be set before it can log anywhere. And `$DEPLOY_LOG` requires the log directory from `config.yaml`. A circular dependency: to use the YAML parser, we need `utils.sh`; to source `utils.sh` usefully, we need the log directory.

The solution is a one-time raw extraction before anything else:

```bash
_LOG_DIR=$(grep -E "^log_dir:" "$CONFIG_FILE" \
    | sed 's/^log_dir:[[:space:]]*//' \
    | xargs)
mkdir -p "$_LOG_DIR"
export DEPLOY_LOG="${_LOG_DIR}/deploy.log"
touch "$DEPLOY_LOG"

source "${SCRIPT_DIR}/utils.sh"
```

This raw `grep` and `sed` reads only `log_dir` — nothing else — without the YAML parser. Once the log directory exists and `$DEPLOY_LOG` is exported, `utils.sh` is sourced. From that point on, all logging functions write to both the terminal and the file.

The `export` is necessary because `install.sh` and `nginx.sh` are called as subprocesses (via `sudo`), not sourced. Exported variables are passed to child processes; unexported variables are not.

---

## Phase 1 — System Installation

```bash
if [[ "$SKIP_INSTALL" == "false" ]]; then
    if [[ "$EUID" -ne 0 ]]; then
        sudo "${SCRIPT_DIR}/install.sh" "$CONFIG_FILE"
    else
        "${SCRIPT_DIR}/install.sh" "$CONFIG_FILE"
    fi
fi
```

The privilege check (`$EUID -ne 0`) determines whether `sudo` is needed. If `deploy.sh` was itself run as root (e.g., in a CI pipeline that runs as root), it calls `install.sh` directly. If run as a regular user, it escalates with `sudo`.

When `--skip-install` is set, this entire block is skipped. Instead, the script verifies that the required commands are already present:

```bash
require_commands docker nginx curl
```

If any of these are missing, the script exits before attempting the Docker or Nginx steps, providing a clear "run install.sh first" message rather than failing mid-way.

---

## Phase 2 — Docker Deployment

```bash
"${SCRIPT_DIR}/docker.sh" "$CONFIG_FILE"
```

`docker.sh` runs as the current user (no sudo). After `install.sh` runs, the current user is in the `docker` group. In a single shell session immediately after `install.sh`, the group membership may not yet be active — a `newgrp docker` or re-login is needed. This is noted in the install documentation.

For automated use (e.g., running `deploy.sh` in a second SSH session after the first ran `install.sh`), the group membership is already active and this step runs without issue.

---

## Phase 3 — Nginx Configuration

```bash
if [[ "$EUID" -ne 0 ]]; then
    sudo "${SCRIPT_DIR}/nginx.sh" "$CONFIG_FILE"
else
    "${SCRIPT_DIR}/nginx.sh" "$CONFIG_FILE"
fi
```

Same privilege escalation pattern as Phase 1. `nginx.sh` needs root to write to `/etc/nginx/` and call `systemctl reload nginx`.

---

## End-to-End Health Check

After all three phases complete, `deploy.sh` performs two health checks:

**Internal check** — confirms the Docker container is responding:

```bash
wait_for_http "http://localhost:${PORT}/" 5 2
```

This is a second check after the one in `docker.sh`. The Docker check happens immediately after the container starts. This one happens after Nginx is configured — a brief window during which the container could theoretically have crashed. Both checks together give high confidence in the final state.

**Public check** — confirms the domain is reachable over HTTPS:

```bash
if curl -fsSL --max-time 10 "https://${DOMAIN}/" > /dev/null 2>&1; then
    log_success "Public endpoint is reachable: https://${DOMAIN}/"
else
    log_warn "Public endpoint did not respond — check DNS/Cloudflare propagation"
fi
```

Unlike the internal check, the public check does not fail the script on a non-200 response. DNS propagation can take minutes. Cloudflare's proxy may need time to recognize the new origin certificate. The API is known to be healthy (the internal check passed); the public-facing layer just needs time to stabilize. The operator is warned, not blocked.

---

## Deployment Summary

On successful completion, `deploy.sh` prints a formatted summary table:

```
  ╔══════════════════════════════════════════════════════════╗
  ║             DEPLOYMENT COMPLETE                          ║
  ╠══════════════════════════════════════════════════════════╣
  ║  Public URL:             https://api.yourdomain.com      ║
  ║  Health check:           https://api.yourdomain.com/     ║
  ║  API docs (Swagger):     https://api.yourdomain.com/docs ║
  ║  Predict endpoint:       https://api.yourdomain.com/predict ║
  ║  Container:              digit-api                       ║
  ║  Image:                  digit-api                       ║
  ║  Log file:               /var/log/digit-api/deploy.log   ║
  ║  Elapsed:                47s                             ║
  ╚══════════════════════════════════════════════════════════╝
```

The elapsed time is calculated as:

```bash
DEPLOY_START=$(date +%s)
# ... all phases ...
DEPLOY_END=$(date +%s)
ELAPSED=$(( DEPLOY_END - DEPLOY_START ))
```

`date +%s` returns the Unix timestamp (seconds since epoch). The difference is the wall-clock seconds the deployment took.

After the table, the script prints the commands for monitoring the running service:

```
[INFO]  To tail prediction logs:
          tail -f /var/log/digit-api/predictions.log

[INFO]  To tail deploy logs:
          tail -f /var/log/digit-api/deploy.log

[INFO]  To check container status:
          docker ps | grep digit-api
```

---

## Reading the Deploy Log

Every action across all four scripts is recorded in `$log_dir/deploy.log`. A complete successful run looks like:

```
[ STEP ] 2025-09-01 14:20:00 — Starting system installation
[INFO]   2025-09-01 14:20:00 — Config: config.yaml
[OK]     2025-09-01 14:20:02 — Package index updated
[WARN]   2025-09-01 14:20:03 — Docker already installed: Docker version 26.1.3
[WARN]   2025-09-01 14:20:03 — Nginx already installed: nginx/1.24.0
[OK]     2025-09-01 14:20:04 — UFW: OpenSSH allowed
[OK]     2025-09-01 14:20:04 — UFW enabled
[ STEP ] 2025-09-01 14:20:05 — Docker deployment — image: digit-api | container: digit-api
[INFO]   2025-09-01 14:20:05 — Found existing container 'digit-api' — stopping and removing...
[OK]     2025-09-01 14:20:08 — Image built: digit-api
[OK]     2025-09-01 14:20:09 — Container started: digit-api
[OK]     2025-09-01 14:20:11 — Health check passed (http://localhost:8000/ returned HTTP 200)
[ STEP ] 2025-09-01 14:20:11 — Nginx configuration — domain: api.yourdomain.com | ssl_mode: cloudflare
[OK]     2025-09-01 14:20:11 — Server block written to /etc/nginx/sites-available/digit-api
[OK]     2025-09-01 14:20:11 — Symlink created: /etc/nginx/sites-enabled/digit-api
[OK]     2025-09-01 14:20:11 — Cloudflare SSL: certificate and key found and secured
[OK]     2025-09-01 14:20:12 — Nginx configuration syntax is valid
[OK]     2025-09-01 14:20:12 — Nginx reloaded
[OK]     2025-09-01 14:20:12 — Nginx is running
[OK]     2025-09-01 14:20:14 — Health check passed (http://localhost:8000/ returned HTTP 200)
[OK]     2025-09-01 14:20:17 — Public endpoint is reachable: https://api.yourdomain.com/
```

Every line is timestamped. Every phase transition is marked with `[ STEP ]`. Errors include the line number of the failing command.

---

## Failure Modes and Recovery

| Failure | Log message | Recovery |
|---|---|---|
| `config.yaml` missing | `[ERROR] Config file not found` | Check path passed as `$1` |
| Docker not installed, `--skip-install` set | `[ERROR] Missing required commands: docker` | Run without `--skip-install` |
| `Dockerfile` not at `app_dir` | `[ERROR] Dockerfile not found at ...` | Check `app_dir` in config |
| Container port already bound | Docker error on `docker run` | Stop whatever is using the port |
| SSL cert missing (Cloudflare mode) | `[ERROR] Cloudflare origin certificate not found at: ...` | Place cert files before running |
| `nginx -t` fails | nginx error output + script exits | Fix the syntax error in the generated config |
| Health check fails after max retries | `[ERROR] Health check failed after N attempts` | Check `docker logs digit-api` |
| Public endpoint unreachable | `[WARN] Public endpoint did not respond` | Wait for DNS / Cloudflare propagation |

In all error cases, the deploy log captures the `[ ERROR ]` line and the `[ STEP ]` context that preceded it, making it possible to pinpoint exactly where the deployment stopped.

---

*← [06 · nginx.sh](../06-nginx/nginx-script.md) | [Index](../../INDEX.md)*
