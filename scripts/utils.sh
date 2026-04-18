#!/usr/bin/env bash
# =============================================================================
# utils.sh — Shared utilities for the Digit Recognizer MLOps automation stack
# =============================================================================
# DO NOT execute this file directly. Source it from other scripts:
#   source "$(dirname "$0")/utils.sh"
# =============================================================================

set -euo pipefail

# ── ANSI colour codes ─────────────────────────────────────────────────────────
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly RESET='\033[0m'

# ── Log file (set by deploy.sh before sourcing; default if run standalone) ────
DEPLOY_LOG="${DEPLOY_LOG:-/var/log/digit-api/deploy.log}"

# ─────────────────────────────────────────────────────────────────────────────
# Logging functions
# Each function writes to stdout (for the terminal) and appends to DEPLOY_LOG.
# ─────────────────────────────────────────────────────────────────────────────

_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

log_info() {
    local msg="$*"
    echo -e "${CYAN}[INFO]${RESET}  $(_timestamp) — $msg"
    echo "[INFO]  $(_timestamp) — $msg" >> "$DEPLOY_LOG" 2>/dev/null || true
}

log_success() {
    local msg="$*"
    echo -e "${GREEN}[OK]${RESET}    $(_timestamp) — $msg"
    echo "[OK]    $(_timestamp) — $msg" >> "$DEPLOY_LOG" 2>/dev/null || true
}

log_warn() {
    local msg="$*"
    echo -e "${YELLOW}[WARN]${RESET}  $(_timestamp) — $msg"
    echo "[WARN]  $(_timestamp) — $msg" >> "$DEPLOY_LOG" 2>/dev/null || true
}

log_error() {
    local msg="$*"
    echo -e "${RED}[ERROR]${RESET} $(_timestamp) — $msg" >&2
    echo "[ERROR] $(_timestamp) — $msg" >> "$DEPLOY_LOG" 2>/dev/null || true
}

log_step() {
    local msg="$*"
    echo ""
    echo -e "${BOLD}${CYAN}══════════════════════════════════════════${RESET}"
    echo -e "${BOLD}${CYAN}  ▶  $msg${RESET}"
    echo -e "${BOLD}${CYAN}══════════════════════════════════════════${RESET}"
    echo "[ STEP ] $(_timestamp) — $msg" >> "$DEPLOY_LOG" 2>/dev/null || true
}

# ─────────────────────────────────────────────────────────────────────────────
# Error handler — automatically called on ERR signal via trap
# Reports the line number and command that failed.
# ─────────────────────────────────────────────────────────────────────────────

handle_error() {
    local exit_code=$?
    local line_number=${1:-unknown}
    log_error "Script failed at line $line_number (exit code: $exit_code)"
    log_error "Check $DEPLOY_LOG for full details"
    exit "$exit_code"
}

# Enable the error trap in any script that sources this file
trap 'handle_error $LINENO' ERR

# ─────────────────────────────────────────────────────────────────────────────
# YAML parser
# Extracts scalar values from a flat key: value YAML file.
# Does not support nested keys, lists, or multi-line values.
# Usage: yaml_get "domain" config.yaml
# ─────────────────────────────────────────────────────────────────────────────

yaml_get() {
    local key="$1"
    local file="$2"

    if [[ ! -f "$file" ]]; then
        log_error "Config file not found: $file"
        exit 1
    fi

    local value
    value=$(grep -E "^${key}[[:space:]]*:" "$file" \
        | sed -E "s/^${key}[[:space:]]*:[[:space:]]*//" \
        | tr -d '"' \
        | tr -d "'" \
        | sed 's/#.*//' \
        | xargs)   # trims surrounding whitespace

    if [[ -z "$value" ]]; then
        log_error "Key '${key}' not found or empty in $file"
        exit 1
    fi

    echo "$value"
}

# ─────────────────────────────────────────────────────────────────────────────
# Dependency checker
# Verifies that a list of commands are available on the system PATH.
# Usage: require_commands docker nginx curl
# ─────────────────────────────────────────────────────────────────────────────

require_commands() {
    local missing=()
    for cmd in "$@"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required commands: ${missing[*]}"
        log_error "Run ./scripts/install.sh first"
        exit 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Root privilege check
# Ensures the script is running as root or via sudo.
# ─────────────────────────────────────────────────────────────────────────────

require_root() {
    if [[ "$EUID" -ne 0 ]]; then
        log_error "This script must be run as root or with sudo"
        exit 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# HTTP health check
# Polls a URL until it returns HTTP 200 or the retry limit is hit.
# Usage: wait_for_http "http://localhost:8000/" 10 2
#          args: url, max_retries, sleep_seconds
# ─────────────────────────────────────────────────────────────────────────────

wait_for_http() {
    local url="$1"
    local max_retries="${2:-10}"
    local sleep_sec="${3:-2}"
    local attempt=1

    log_info "Waiting for $url to become healthy..."

    while [[ $attempt -le $max_retries ]]; do
        local http_code
        http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "$url" || echo "000")

        if [[ "$http_code" == "200" ]]; then
            log_success "Health check passed ($url returned HTTP 200)"
            return 0
        fi

        log_warn "Attempt $attempt/$max_retries — got HTTP $http_code, retrying in ${sleep_sec}s..."
        sleep "$sleep_sec"
        ((attempt++))
    done

    log_error "Health check failed after $max_retries attempts"
    return 1
}

# ─────────────────────────────────────────────────────────────────────────────
# Ensure log directory exists and is writable
# ─────────────────────────────────────────────────────────────────────────────

ensure_log_dir() {
    local log_dir
    log_dir="$(dirname "$DEPLOY_LOG")"
    if [[ ! -d "$log_dir" ]]; then
        mkdir -p "$log_dir"
    fi
    touch "$DEPLOY_LOG"
}
