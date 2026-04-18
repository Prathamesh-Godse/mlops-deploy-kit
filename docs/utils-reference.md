# 03 · utils.sh

*← [Index](../../INDEX.md) · [Config Reference](../02-config/config-reference.md)*

---

## Purpose

`utils.sh` is the shared library of the automation stack. It is never executed directly. Every other script begins by sourcing it:

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"
```

Using `${BASH_SOURCE[0]}` instead of `$0` is deliberate — it resolves correctly whether the script is executed directly, sourced, or called from another directory.

---

## Logging Functions

All logging functions write to two destinations simultaneously:

1. **Terminal (stdout/stderr)** — with ANSI colour codes for readability
2. **`$DEPLOY_LOG`** — plain text (no colour codes), appended on every call

The `$DEPLOY_LOG` variable is set by the calling script before sourcing `utils.sh`. If it's not set, the functions fall back to `/var/log/digit-api/deploy.log`. The `|| true` at the end of each log-to-file operation ensures that a non-writable log path does not crash the script — it degrades gracefully to terminal-only output.

---

### `log_info`

General informational messages. Used for state reporting and progress updates.

```bash
log_info "Building Docker image: digit-api"
```

Output:
```
[INFO]  2025-09-01 14:23:01 — Building Docker image: digit-api
```

Colour: cyan.

---

### `log_success`

Confirms that a step completed without error.

```bash
log_success "Docker installed: Docker version 26.1.3"
```

Output:
```
[OK]    2025-09-01 14:23:45 — Docker installed: Docker version 26.1.3
```

Colour: green.

---

### `log_warn`

Non-fatal conditions that should be noted. Used when skipping a step because it's already done, or when a soft check passes with caveats.

```bash
log_warn "Docker already installed — skipping"
```

Output:
```
[WARN]  2025-09-01 14:23:02 — Docker already installed — skipping
```

Colour: yellow.

---

### `log_error`

Fatal error conditions. Written to stderr on the terminal, to the log file, and typically followed immediately by `exit 1`.

```bash
log_error "Dockerfile not found at ${APP_DIR}/Dockerfile"
exit 1
```

Output:
```
[ERROR] 2025-09-01 14:25:11 — Dockerfile not found at /home/ubuntu/digit-api/Dockerfile
```

Colour: red, written to stderr.

---

### `log_step`

Prints a visual section header to mark the beginning of a major phase. Makes long terminal output scannable.

```bash
log_step "Building Docker image"
```

Output:
```

══════════════════════════════════════════
  ▶  Building Docker image
══════════════════════════════════════════
```

Also writes `[ STEP ]` to the log file. Colour: bold cyan.

---

## Error Handler

```bash
handle_error() {
    local exit_code=$?
    local line_number=${1:-unknown}
    log_error "Script failed at line $line_number (exit code: $exit_code)"
    log_error "Check $DEPLOY_LOG for full details"
    exit "$exit_code"
}

trap 'handle_error $LINENO' ERR
```

This trap is activated by `source`-ing `utils.sh`. It intercepts any command that exits with a non-zero code (because `set -e` is active in all scripts) and logs the exact line number before the script terminates. Without this, a failed command produces no context — only a bare exit code.

The trap fires in the sourcing script's scope, so `$LINENO` refers to the line in the script that failed, not a line in `utils.sh`.

---

## `yaml_get`

Extracts a scalar value from a flat YAML file.

```bash
yaml_get "domain" config.yaml
# → api.yourdomain.com

yaml_get "port" config.yaml
# → 8000
```

If the key is not found or is empty, the function logs an error and exits. There is no silent failure.

See [Config Reference](../02-config/config-reference.md) for a full explanation of the parser.

---

## `require_commands`

Checks that a list of commands exist on the `$PATH`. Exits with an error listing all missing commands if any are absent.

```bash
require_commands docker nginx curl
```

Useful at the top of scripts to provide a clear diagnostic when a dependency is missing, rather than a cryptic "command not found" error mid-run.

---

## `require_root`

Verifies that the script is running as root (`$EUID -eq 0`). Exits if not.

```bash
require_root
```

Called at the top of `install.sh` and `nginx.sh`. Not needed in `docker.sh` (which runs as a regular user with docker group membership) or `deploy.sh` (which escalates with `sudo` for the two scripts that need it).

---

## `wait_for_http`

Polls an HTTP URL until it returns `200 OK` or the retry limit is reached.

```bash
wait_for_http "http://localhost:8000/" 10 2
# args: url, max_retries, sleep_seconds_between_retries
```

Used after `docker run` to confirm Uvicorn started correctly before Nginx configuration is applied. Also used at the end of `deploy.sh` for the final health check.

Uses `curl -s -o /dev/null -w "%{http_code}"` to retrieve only the HTTP status code. If `curl` fails entirely (e.g., connection refused), the exit code is caught and mapped to `000`.

---

## `ensure_log_dir`

Creates the directory containing `$DEPLOY_LOG` if it doesn't exist, and touches the log file to confirm it's writable.

```bash
ensure_log_dir
```

Called near the top of every script, after `DEPLOY_LOG` is set. Ensures that subsequent logging calls don't fail silently because the directory doesn't exist.

---

## `set -euo pipefail`

Every script (including those that source `utils.sh`) sets these options:

| Option | Effect |
|---|---|
| `-e` | Exit immediately if any command fails |
| `-u` | Treat unset variables as errors |
| `-o pipefail` | Fail a pipeline if any command in it fails (not just the last) |

`pipefail` is particularly important for chains like `curl ... | gpg ...` — without it, a failed `curl` would be hidden by a successful `gpg`. With `pipefail`, the pipeline fails if either command fails.

---

*→ Next: [04 · install.sh](../04-install/install-script.md)*
