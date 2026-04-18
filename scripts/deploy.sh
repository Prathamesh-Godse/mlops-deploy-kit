#!/usr/bin/env bash
# =============================================================================
# deploy.sh — One-command deployment orchestrator
# =============================================================================
# Usage:
#   ./scripts/deploy.sh config.yaml [--skip-install]
#
# Flags:
#   --skip-install   Skip the system installation step (Docker, Nginx, UFW).
#                    Use when the server is already set up and you only
#                    need to re-deploy the container and Nginx config.
#
# What it does (in order):
#   0. Validates that config.yaml exists and is readable
#   1. [install]  sudo ./scripts/install.sh  — installs Docker, Nginx, UFW
#   2. [docker]   ./scripts/docker.sh        — builds image, runs container
#   3. [nginx]    sudo ./scripts/nginx.sh    — configures reverse proxy + SSL
#   4. Final end-to-end health check via the public domain
#   5. Prints a deployment summary
#
# The entire run is logged to $log_dir/deploy.log (from config.yaml).
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─────────────────────────────────────────────────────────────────────────────
# Parse arguments
# ─────────────────────────────────────────────────────────────────────────────

if [[ $# -lt 1 ]]; then
    echo ""
    echo "  Usage: $0 config.yaml [--skip-install]"
    echo ""
    echo "  config.yaml     Path to deployment configuration file"
    echo "  --skip-install  Skip Docker/Nginx/UFW installation step"
    echo ""
    exit 1
fi

CONFIG_FILE="$1"
SKIP_INSTALL=false

if [[ "${2:-}" == "--skip-install" ]]; then
    SKIP_INSTALL=true
fi

# ─────────────────────────────────────────────────────────────────────────────
# Validate config file
# ─────────────────────────────────────────────────────────────────────────────

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "[ERROR] Config file not found: $CONFIG_FILE"
    exit 1
fi

# Bootstrap the log dir before sourcing utils (utils.sh needs DEPLOY_LOG set)
# We do a raw grep here because utils.sh hasn't been sourced yet
_LOG_DIR=$(grep -E "^log_dir:" "$CONFIG_FILE" | sed 's/^log_dir:[[:space:]]*//' | xargs)
mkdir -p "$_LOG_DIR"
export DEPLOY_LOG="${_LOG_DIR}/deploy.log"
touch "$DEPLOY_LOG"

source "${SCRIPT_DIR}/utils.sh"

# ─────────────────────────────────────────────────────────────────────────────
# Read config
# ─────────────────────────────────────────────────────────────────────────────

DOMAIN="$(yaml_get    "domain"    "$CONFIG_FILE")"
PORT="$(yaml_get      "port"      "$CONFIG_FILE")"
CONTAINER="$(yaml_get "docker_container" "$CONFIG_FILE")"
IMAGE="$(yaml_get     "docker_image"     "$CONFIG_FILE")"

# ─────────────────────────────────────────────────────────────────────────────
# Deployment banner
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}${CYAN}"
echo "  ╔══════════════════════════════════════════════════╗"
echo "  ║     Digit Recognizer — MLOps Deployment          ║"
echo "  ║     $(date '+%Y-%m-%d %H:%M:%S')                          ║"
echo "  ╚══════════════════════════════════════════════════╝"
echo -e "${RESET}"

log_info "Config     : $CONFIG_FILE"
log_info "Domain     : $DOMAIN"
log_info "Port       : $PORT"
log_info "Container  : $CONTAINER"
log_info "Image      : $IMAGE"
log_info "Log file   : $DEPLOY_LOG"
log_info "Skip install: $SKIP_INSTALL"

DEPLOY_START=$(date +%s)

# ─────────────────────────────────────────────────────────────────────────────
# Phase 1 — System installation
# ─────────────────────────────────────────────────────────────────────────────

if [[ "$SKIP_INSTALL" == "false" ]]; then
    log_step "Phase 1 of 3 — System Installation"

    if [[ "$EUID" -ne 0 ]]; then
        log_info "Escalating to sudo for install.sh..."
        sudo "${SCRIPT_DIR}/install.sh" "$CONFIG_FILE"
    else
        "${SCRIPT_DIR}/install.sh" "$CONFIG_FILE"
    fi

    log_success "Phase 1 complete — system installation done"
else
    log_warn "Phase 1 skipped (--skip-install flag set)"
    log_info "Verifying required commands exist..."
    require_commands docker nginx curl
    log_success "All required commands present"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Phase 2 — Docker deployment
# ─────────────────────────────────────────────────────────────────────────────

log_step "Phase 2 of 3 — Docker Deployment"

"${SCRIPT_DIR}/docker.sh" "$CONFIG_FILE"

log_success "Phase 2 complete — container is running"

# ─────────────────────────────────────────────────────────────────────────────
# Phase 3 — Nginx configuration
# ─────────────────────────────────────────────────────────────────────────────

log_step "Phase 3 of 3 — Nginx Configuration"

if [[ "$EUID" -ne 0 ]]; then
    log_info "Escalating to sudo for nginx.sh..."
    sudo "${SCRIPT_DIR}/nginx.sh" "$CONFIG_FILE"
else
    "${SCRIPT_DIR}/nginx.sh" "$CONFIG_FILE"
fi

log_success "Phase 3 complete — Nginx configured and reloaded"

# ─────────────────────────────────────────────────────────────────────────────
# Final end-to-end health check
# ─────────────────────────────────────────────────────────────────────────────

log_step "End-to-end health check"

log_info "Checking internal endpoint: http://localhost:${PORT}/"
wait_for_http "http://localhost:${PORT}/" 5 2

log_info "Checking public endpoint: https://${DOMAIN}/"
# Give DNS/Cloudflare propagation a moment if needed
sleep 3
if curl -fsSL --max-time 10 "https://${DOMAIN}/" > /dev/null 2>&1; then
    log_success "Public endpoint is reachable: https://${DOMAIN}/"
else
    log_warn "Public endpoint did not respond in time — check DNS/Cloudflare propagation"
    log_warn "Internal API is healthy; Nginx is running. Public access may take a few minutes."
fi

# ─────────────────────────────────────────────────────────────────────────────
# Deployment summary
# ─────────────────────────────────────────────────────────────────────────────

DEPLOY_END=$(date +%s)
ELAPSED=$(( DEPLOY_END - DEPLOY_START ))

echo ""
echo -e "${BOLD}${GREEN}"
echo "  ╔══════════════════════════════════════════════════════════╗"
echo "  ║             DEPLOYMENT COMPLETE                          ║"
echo "  ╠══════════════════════════════════════════════════════════╣"
printf  "  ║  %-24s %-32s  ║\n" "Public URL:"      "https://${DOMAIN}"
printf  "  ║  %-24s %-32s  ║\n" "Health check:"    "https://${DOMAIN}/"
printf  "  ║  %-24s %-32s  ║\n" "API docs (Swagger):" "https://${DOMAIN}/docs"
printf  "  ║  %-24s %-32s  ║\n" "Predict endpoint:"  "https://${DOMAIN}/predict"
printf  "  ║  %-24s %-32s  ║\n" "Container:"       "$CONTAINER"
printf  "  ║  %-24s %-32s  ║\n" "Image:"           "$IMAGE"
printf  "  ║  %-24s %-32s  ║\n" "Log file:"        "$DEPLOY_LOG"
printf  "  ║  %-24s %-32s  ║\n" "Elapsed:"         "${ELAPSED}s"
echo "  ╚══════════════════════════════════════════════════════════╝"
echo -e "${RESET}"

log_info "To tail prediction logs:"
log_info "  tail -f ${_LOG_DIR}/predictions.log"
log_info ""
log_info "To tail deploy logs:"
log_info "  tail -f $DEPLOY_LOG"
log_info ""
log_info "To check container status:"
log_info "  docker ps | grep $CONTAINER"
