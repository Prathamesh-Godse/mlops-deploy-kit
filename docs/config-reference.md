# 02 · Config Reference

*← [Index](../../INDEX.md) · [Overview](../01-overview/automation-overview.md)*

---

## The Config File

`config.yaml` is the single source of truth for every deployment variable. Every script reads from it. Nothing is hardcoded.

It is a flat key-value YAML file — no nesting, no lists. The parser inside `utils.sh` is a purpose-built Bash function that handles this subset without requiring `yq` or any external tool.

---

## Full Reference

```yaml
# ─────────────────────────────────────────────────────────────────────────────
# Digit Recognizer MLOps — Deployment Configuration
# ─────────────────────────────────────────────────────────────────────────────

domain: api.yourdomain.com
docker_image: digit-api
docker_container: digit-api
port: 8000
restart_policy: unless-stopped
app_dir: /home/ubuntu/digit-api
log_dir: /var/log/digit-api
nginx_config_name: digit-api
ssl_mode: cloudflare
certbot_email: your@email.com
```

---

## Key-by-Key Documentation

### `domain`

The public-facing hostname for the API.

```yaml
domain: api.yourdomain.com
```

Used in:
- `nginx.sh` — written into the `server_name` directive and the log file paths
- `deploy.sh` — used for the final public endpoint health check

Must be a fully qualified domain name that is pointed at the server's IP (via DNS A record). For Cloudflare setups, the orange cloud proxy must be enabled.

---

### `docker_image`

The tag name for the Docker image that `docker build` creates.

```yaml
docker_image: digit-api
```

Used in:
- `docker.sh` — passed to `docker build -t` and `docker run`

Must be a valid Docker image name (lowercase, alphanumeric, hyphens allowed). Changing this value causes a new image to be built with the new name; the old image is not automatically removed.

---

### `docker_container`

The name assigned to the running container.

```yaml
docker_container: digit-api
```

Used in:
- `docker.sh` — passed to `docker run --name`

The script checks for an existing container with this exact name before running. If one exists, it is stopped and removed first. This is what makes re-deployments safe and the script idempotent.

---

### `port`

The port the FastAPI application listens on inside the container, and the host port it is mapped to.

```yaml
port: 8000
```

Used in:
- `docker.sh` — passed to `docker run -p <port>:<port>`
- `nginx.sh` — written into the `proxy_pass http://localhost:<port>` directive
- `deploy.sh` — used for the internal health check URL

UFW does not open this port to the internet. Only Nginx on localhost routes traffic to it.

---

### `restart_policy`

Docker's container restart policy.

```yaml
restart_policy: unless-stopped
```

Valid Docker values:

| Value | Behavior |
|---|---|
| `no` | Never restart automatically |
| `always` | Always restart, including on Docker daemon start |
| `on-failure` | Restart only on non-zero exit code |
| `unless-stopped` | Restart always, except when explicitly stopped |

`unless-stopped` is the recommended value for production. The container survives server reboots without any systemd service unit.

---

### `app_dir`

Absolute path to the project directory on the server — the directory that contains the `Dockerfile`.

```yaml
app_dir: /home/ubuntu/digit-api
```

Used in:
- `docker.sh` — the build context path and `--file` argument for `docker build`

The directory must exist on the server and must contain:
- `Dockerfile`
- `app/main.py`
- `app/model.pkl`
- `app/requirements.txt`

---

### `log_dir`

Absolute path to the directory where deployment logs and prediction logs are written on the host.

```yaml
log_dir: /var/log/digit-api
```

Used in:
- All scripts — `DEPLOY_LOG` is set to `${log_dir}/deploy.log`
- `docker.sh` — mounted into the container at `/app/logs` so `predictions.log` persists outside the container

The directory is created automatically if it does not exist. It survives container replacements and server reboots.

---

### `nginx_config_name`

The filename used for the Nginx site configuration in `sites-available` and `sites-enabled`.

```yaml
nginx_config_name: digit-api
```

Used in:
- `nginx.sh` — the config is written to `/etc/nginx/sites-available/<nginx_config_name>` and symlinked to `/etc/nginx/sites-enabled/<nginx_config_name>`

Also used as the base name for Nginx access and error log files:
- `/var/log/nginx/<nginx_config_name>.access.log`
- `/var/log/nginx/<nginx_config_name>.error.log`

---

### `ssl_mode`

Controls which SSL provisioning method `nginx.sh` uses.

```yaml
ssl_mode: cloudflare   # or: certbot
```

**`cloudflare`**: Expects a Cloudflare Origin Certificate to already be on the server at:
- `/etc/ssl/certs/<nginx_config_name>.crt`
- `/etc/ssl/private/<nginx_config_name>.key`

`nginx.sh` validates that both files exist and that the key is `chmod 600`. The Nginx config references these paths directly.

**`certbot`**: Runs `certbot --nginx` automatically, which:
1. Obtains a Let's Encrypt certificate for `domain`
2. Writes the certificate to the system's certbot storage
3. Modifies the Nginx config to use the certbot-managed paths
4. Runs `certbot renew --dry-run` to confirm auto-renewal is configured

Choose `cloudflare` if Cloudflare is the DNS provider and you're using Cloudflare's Full SSL mode (recommended for consistency with the WordPress server setup). Choose `certbot` for standalone servers not behind Cloudflare.

---

### `certbot_email`

The email address used when registering with Let's Encrypt via Certbot.

```yaml
certbot_email: your@email.com
```

Only read when `ssl_mode: certbot`. Ignored entirely for Cloudflare mode. Let's Encrypt sends certificate expiry notices to this address.

---

## How the YAML Parser Works

`utils.sh` contains a `yaml_get` function that extracts values without any external YAML tool:

```bash
yaml_get() {
    local key="$1"
    local file="$2"

    local value
    value=$(grep -E "^${key}[[:space:]]*:" "$file" \
        | sed -E "s/^${key}[[:space:]]*:[[:space:]]*//" \
        | tr -d '"' \
        | tr -d "'" \
        | sed 's/#.*//' \
        | xargs)

    if [[ -z "$value" ]]; then
        log_error "Key '${key}' not found or empty in $file"
        exit 1
    fi

    echo "$value"
}
```

It: finds the line starting with the key, strips the key and colon, removes quotes, strips inline comments, and trims whitespace. It exits with an error if a key is missing or empty, so missing config values are caught immediately at script start rather than failing silently mid-run.

**Limitation:** This parser handles flat key-value pairs only. Nested YAML, lists, and multi-line values are not supported. The config file is intentionally kept flat to avoid requiring `yq` or Python as a dependency.

---

*→ Next: [03 · utils.sh](../03-utils/utils-reference.md)*
