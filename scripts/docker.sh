#!/usr/bin/env bash
# =============================================================================
# docker.sh — Docker image build and container lifecycle management
# =============================================================================
# Usage (standalone):
#   ./scripts/docker.sh config.yaml
#
# Or called automatically by deploy.sh.
#
# What it does:
#   1. Reads all Docker config from config.yaml
#   2. Ensures the log directory exists on the host
#   3. Stops and removes any existing container with the same name
#   4. Builds the Docker image from the Dockerfile in app_dir
#   5. Runs the new container with restart policy and log volume
#   6. Runs a health check to confirm the container is responding
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# ─────────────────────────────────────────────────────────────────────────────
# Validate input
# ─────────────────────────────────────────────────────────────────────────────

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 config.yaml"
    exit 1
fi

CONFIG_FILE="$1"

# ─────────────────────────────────────────────────────────────────────────────
# Load config values
# ─────────────────────────────────────────────────────────────────────────────

DOCKER_IMAGE="$(yaml_get "docker_image"     "$CONFIG_FILE")"
CONTAINER="$(yaml_get    "docker_container" "$CONFIG_FILE")"
PORT="$(yaml_get         "port"             "$CONFIG_FILE")"
RESTART="$(yaml_get      "restart_policy"   "$CONFIG_FILE")"
APP_DIR="$(yaml_get      "app_dir"          "$CONFIG_FILE")"
LOG_DIR="$(yaml_get      "log_dir"          "$CONFIG_FILE")"

DEPLOY_LOG="${LOG_DIR}/deploy.log"
ensure_log_dir

log_step "Docker deployment — image: $DOCKER_IMAGE | container: $CONTAINER | port: $PORT"

# ─────────────────────────────────────────────────────────────────────────────
# Verify Docker is available
# ─────────────────────────────────────────────────────────────────────────────

require_commands docker

# ─────────────────────────────────────────────────────────────────────────────
# Step 1 — Ensure host log directory exists
# ─────────────────────────────────────────────────────────────────────────────

log_step "Preparing host log directory"

if [[ ! -d "$LOG_DIR" ]]; then
    mkdir -p "$LOG_DIR"
    log_success "Created log directory: $LOG_DIR"
else
    log_warn "Log directory already exists: $LOG_DIR"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Step 2 — Stop and remove existing container (if any)
# ─────────────────────────────────────────────────────────────────────────────

log_step "Checking for existing container"

if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    log_info "Found existing container '$CONTAINER' — stopping and removing..."
    docker stop "$CONTAINER"  && log_info "Stopped: $CONTAINER"
    docker rm   "$CONTAINER"  && log_success "Removed: $CONTAINER"
else
    log_info "No existing container named '$CONTAINER' — nothing to remove"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Step 3 — Build the Docker image
# ─────────────────────────────────────────────────────────────────────────────

log_step "Building Docker image: $DOCKER_IMAGE"

if [[ ! -f "${APP_DIR}/Dockerfile" ]]; then
    log_error "Dockerfile not found at ${APP_DIR}/Dockerfile"
    exit 1
fi

docker build \
    --tag "$DOCKER_IMAGE" \
    --file "${APP_DIR}/Dockerfile" \
    "$APP_DIR"

log_success "Image built: $DOCKER_IMAGE"
docker images "$DOCKER_IMAGE" --format "  ID: {{.ID}}  Size: {{.Size}}  Created: {{.CreatedAt}}"

# ─────────────────────────────────────────────────────────────────────────────
# Step 4 — Run the container
# ─────────────────────────────────────────────────────────────────────────────

log_step "Starting container: $CONTAINER"

docker run \
    --detach \
    --name "$CONTAINER" \
    --publish "${PORT}:${PORT}" \
    --restart "$RESTART" \
    --volume "${LOG_DIR}:/app/logs" \
    "$DOCKER_IMAGE"

log_success "Container started: $CONTAINER"
docker ps --filter "name=${CONTAINER}" \
    --format "  Status: {{.Status}}  Ports: {{.Ports}}"

# ─────────────────────────────────────────────────────────────────────────────
# Step 5 — Health check
# ─────────────────────────────────────────────────────────────────────────────

log_step "Running health check on localhost:${PORT}"

# Give Uvicorn a moment to start before polling
sleep 2

wait_for_http "http://localhost:${PORT}/" 10 2

# ─────────────────────────────────────────────────────────────────────────────
# Done
# ─────────────────────────────────────────────────────────────────────────────

echo ""
log_success "════════════════════════════════════════════════"
log_success "  Docker deployment complete"
log_success "  Container : $CONTAINER"
log_success "  Image     : $DOCKER_IMAGE"
log_success "  Internal  : http://localhost:$PORT"
log_success "  Restart   : $RESTART"
log_success "════════════════════════════════════════════════"
