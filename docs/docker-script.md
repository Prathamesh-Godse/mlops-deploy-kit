# 05 · docker.sh

*← [Index](../../INDEX.md) · [install.sh](../04-install/install-script.md)*

---

## Purpose

`docker.sh` manages the full lifecycle of the ML API container: preparing the host environment, cleaning up any previous deployment, building a fresh image, running the container with the correct configuration, and confirming it is healthy.

It is called by `deploy.sh` during Phase 2, or it can be run independently to re-deploy only the container without touching Nginx or system packages.

---

## Usage

```bash
./scripts/docker.sh config.yaml
```

Does not require root (assumes the user is in the `docker` group after `install.sh` ran).

---

## Config Values Used

| Key | Used for |
|---|---|
| `docker_image` | `docker build -t <image>` and `docker run <image>` |
| `docker_container` | `docker run --name <container>` and stop/remove lookup |
| `port` | `-p <port>:<port>` mapping |
| `restart_policy` | `--restart <policy>` |
| `app_dir` | Build context path for `docker build` |
| `log_dir` | Host log directory, mounted as volume |

---

## Step-by-Step Walkthrough

### Step 1 — Ensure host log directory

```bash
if [[ ! -d "$LOG_DIR" ]]; then
    mkdir -p "$LOG_DIR"
fi
```

Before running the container, the host directory for log persistence is created if it doesn't exist. This directory is mounted into the container in Step 4. If it didn't exist at container start time, Docker would create it — but owned by root, which can cause permission issues. Creating it explicitly beforehand gives the current user ownership.

---

### Step 2 — Stop and remove existing container

```bash
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    docker stop "$CONTAINER"
    docker rm   "$CONTAINER"
fi
```

`docker ps -a` lists all containers — running and stopped. The `--format '{{.Names}}'` flag outputs only names, one per line. The `grep` uses `^` and `$` anchors to match the exact name, not a prefix of a longer name.

This step is what makes re-deployments safe. Without it, `docker run --name digit-api` would fail with "name already in use" if an old container exists. Stopping and removing first allows the new container to take the name cleanly.

If no container with that name exists, the `grep` returns non-zero and the `if` block is skipped — no error.

---

### Step 3 — Build the Docker image

```bash
docker build \
    --tag "$DOCKER_IMAGE" \
    --file "${APP_DIR}/Dockerfile" \
    "$APP_DIR"
```

- `--tag` assigns the image name from `config.yaml`
- `--file` points to the Dockerfile in the `app_dir` (required when the build context and Dockerfile are not in the current directory)
- The final argument `"$APP_DIR"` is the build context — the directory Docker sends to the build daemon

The Dockerfile's layer ordering (copy `requirements.txt` → `pip install` → copy code) ensures that a code-only change uses the cached `pip install` layer. The first build after a dependency change is the only expensive one.

After building, the script prints the image's ID and size for the log:

```bash
docker images "$DOCKER_IMAGE" --format "  ID: {{.ID}}  Size: {{.Size}}  Created: {{.CreatedAt}}"
```

---

### Step 4 — Run the container

```bash
docker run \
    --detach \
    --name "$CONTAINER" \
    --publish "${PORT}:${PORT}" \
    --restart "$RESTART" \
    --volume "${LOG_DIR}:/app/logs" \
    "$DOCKER_IMAGE"
```

Each flag:

| Flag | Value | Purpose |
|---|---|---|
| `--detach` | — | Run in background; return control to the shell |
| `--name` | `$CONTAINER` | Assign a fixed name for management commands |
| `--publish` | `PORT:PORT` | Map host port to container port |
| `--restart` | `$RESTART` | Auto-restart policy (from config) |
| `--volume` | `LOG_DIR:/app/logs` | Persist logs outside the container |
| (positional) | `$DOCKER_IMAGE` | The image to instantiate |

The volume mount connects the host's `$LOG_DIR` to `/app/logs` inside the container. The FastAPI application writes `predictions.log` to `/app/logs/predictions.log`, which maps to `${LOG_DIR}/predictions.log` on the host. This file persists across container replacements.

---

### Step 5 — Health check

```bash
sleep 2
wait_for_http "http://localhost:${PORT}/" 10 2
```

A 2-second pause before polling gives Uvicorn time to start. The `wait_for_http` function (from `utils.sh`) then polls `http://localhost:8000/` up to 10 times, with 2 seconds between attempts. If the health endpoint returns HTTP 200, the function returns success. If it hasn't responded after 10 attempts (20 seconds), it exits with an error.

This health check confirms the container is actually serving traffic before `deploy.sh` proceeds to configure Nginx. Without it, Nginx could be configured to proxy to a port that isn't responding yet.

---

## Rebuild Cycle

On a subsequent re-deployment:

1. `docker stop digit-api` — sends SIGTERM to Uvicorn, waits for it to finish
2. `docker rm digit-api` — deletes the container (not the image)
3. `docker build -t digit-api .` — rebuilds image (code layers re-run; dep layers from cache)
4. `docker run ...` — new container starts with the updated code

The old image (`digit-api`) is overwritten by the new build. Docker keeps the old image layers in cache for fast rebuilds. To remove all unused images and free disk space:

```bash
docker image prune -f
```

---

## Container Status Verification

After `docker.sh` completes, check the container state:

```bash
docker ps | grep digit-api
docker logs digit-api --tail 30
docker stats digit-api --no-stream
```

Expected `docker ps` output:

```
CONTAINER ID   IMAGE       COMMAND                  CREATED         STATUS         PORTS                    NAMES
a3f2b8c1d4e5   digit-api   "uvicorn main:app --…"   5 seconds ago   Up 4 seconds   0.0.0.0:8000->8000/tcp   digit-api
```

---

*→ Next: [06 · nginx.sh](../06-nginx/nginx-script.md)*
