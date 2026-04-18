#!/usr/bin/env bash
# =============================================================================
# install.sh — System setup: Docker, Nginx, UFW
# =============================================================================
# Usage:
#   sudo ./scripts/install.sh config.yaml
#
# What it does:
#   1. Reads config.yaml for log_dir
#   2. Installs Docker (official repository method)
#   3. Adds the invoking user to the docker group
#   4. Installs Nginx
#   5. Configures UFW firewall rules
#
# Idempotent: safe to run multiple times. Already-installed components
# are detected and skipped rather than re-installed.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# ─────────────────────────────────────────────────────────────────────────────
# Validate input
# ─────────────────────────────────────────────────────────────────────────────

if [[ $# -lt 1 ]]; then
    echo "Usage: sudo $0 config.yaml"
    exit 1
fi

CONFIG_FILE="$1"
require_root

# ─────────────────────────────────────────────────────────────────────────────
# Load config
# ─────────────────────────────────────────────────────────────────────────────

LOG_DIR="$(yaml_get "log_dir" "$CONFIG_FILE")"
DEPLOY_LOG="${LOG_DIR}/deploy.log"
ensure_log_dir

log_step "Starting system installation"
log_info "Config: $CONFIG_FILE"
log_info "Log:    $DEPLOY_LOG"

# ─────────────────────────────────────────────────────────────────────────────
# Step 1 — System update
# ─────────────────────────────────────────────────────────────────────────────

log_step "Updating package index"
apt-get update -qq
log_success "Package index updated"

# ─────────────────────────────────────────────────────────────────────────────
# Step 2 — Install Docker
# ─────────────────────────────────────────────────────────────────────────────

log_step "Installing Docker"

if command -v docker &>/dev/null; then
    log_warn "Docker already installed: $(docker --version)"
else
    log_info "Installing Docker prerequisites..."
    apt-get install -y -qq \
        ca-certificates \
        curl \
        gnupg \
        lsb-release

    log_info "Adding Docker GPG key..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    log_info "Adding Docker apt repository..."
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
        | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update -qq
    apt-get install -y -qq \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin

    systemctl enable --now docker
    log_success "Docker installed: $(docker --version)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Step 3 — Add invoking user to docker group
# ─────────────────────────────────────────────────────────────────────────────

log_step "Configuring Docker group"

REAL_USER="${SUDO_USER:-$USER}"

if id -nG "$REAL_USER" | grep -qw docker; then
    log_warn "User '$REAL_USER' is already in the docker group"
else
    usermod -aG docker "$REAL_USER"
    log_success "User '$REAL_USER' added to the docker group"
    log_warn "Log out and back in (or run 'newgrp docker') for the group change to take effect"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Step 4 — Install Nginx
# ─────────────────────────────────────────────────────────────────────────────

log_step "Installing Nginx"

if command -v nginx &>/dev/null; then
    log_warn "Nginx already installed: $(nginx -v 2>&1)"
else
    apt-get install -y -qq nginx
    systemctl enable --now nginx
    log_success "Nginx installed: $(nginx -v 2>&1)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Step 5 — Configure UFW firewall
# ─────────────────────────────────────────────────────────────────────────────

log_step "Configuring UFW firewall"

if ! command -v ufw &>/dev/null; then
    apt-get install -y -qq ufw
fi

ufw allow OpenSSH
log_success "UFW: OpenSSH allowed"

ufw allow 'Nginx Full'
log_success "UFW: Nginx Full (80/443) allowed"

log_info "UFW: Port 8000 intentionally NOT opened — internal only via Nginx"

ufw --force enable
log_success "UFW enabled"

ufw status numbered

# ─────────────────────────────────────────────────────────────────────────────
# Done
# ─────────────────────────────────────────────────────────────────────────────

echo ""
log_success "════════════════════════════════════════"
log_success "  System installation complete"
log_success "  Docker  : $(docker --version)"
log_success "  Nginx   : $(nginx -v 2>&1)"
log_success "  UFW     : active"
log_success "════════════════════════════════════════"
