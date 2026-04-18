# 06 · nginx.sh

*← [Index](../../INDEX.md) · [docker.sh](../05-docker/docker-script.md)*

---

## Purpose

`nginx.sh` generates a fully configured Nginx server block from `config.yaml` values, writes it to the correct location, enables it, handles SSL based on the configured mode, tests the configuration, and reloads Nginx. The generated config is not a template file — it is built entirely by the script at deploy time from current config values.

It is called by `deploy.sh` during Phase 3, or independently when only the Nginx configuration needs to change.

---

## Usage

```bash
sudo ./scripts/nginx.sh config.yaml
```

Requires root (`nginx.sh` writes to `/etc/nginx/` and calls `systemctl`).

---

## Config Values Used

| Key | Used for |
|---|---|
| `domain` | `server_name`, log file names, health check URL |
| `port` | `proxy_pass http://localhost:<port>` |
| `nginx_config_name` | Filenames in `sites-available` and `sites-enabled`, log paths |
| `ssl_mode` | Which SSL path to take (`cloudflare` or `certbot`) |
| `certbot_email` | Certbot registration (only when `ssl_mode: certbot`) |

---

## Step-by-Step Walkthrough

### Step 1 — Generate the Nginx server block

The server block is written using a heredoc directly to `/etc/nginx/sites-available/<nginx_config_name>`:

```bash
cat > "$NGINX_AVAILABLE" << NGINX_CONF
...
NGINX_CONF
```

The heredoc contains the full server block with values substituted from config variables at generation time. Every `$variable` inside is expanded by the shell. Literals that Nginx needs as `$` signs (like `$host`, `$remote_addr`) are escaped as `\$host`, `\$remote_addr` inside the heredoc.

The generated config includes:

- An HTTP server block on port 80 that redirects everything to HTTPS with a `301`
- An HTTPS server block on port 443 with:
  - SSL certificate and key paths (varies by ssl_mode)
  - TLSv1.2/TLSv1.3 only (TLS 1.0 and 1.1 disabled)
  - Strong cipher suite
  - SSL session caching
  - Four HTTP security headers
  - Access and error log paths specific to this service
  - `proxy_pass http://localhost:<port>` with full proxy header forwarding

A generation timestamp is written in a comment at the top of the file, making it easy to identify when a config was last regenerated.

---

### Step 2 — Enable the site

```bash
if [[ -L "$NGINX_ENABLED" ]]; then
    rm "$NGINX_ENABLED"
fi
ln -s "$NGINX_AVAILABLE" "$NGINX_ENABLED"
```

The symlink approach is Nginx's standard mechanism for enabling and disabling sites without deleting configuration files. If a symlink already exists (from a previous deployment), it is removed first and re-created. This ensures the symlink always points to the current version of the config file.

---

### Step 3 — SSL handling

#### Cloudflare mode

```bash
if [[ ! -f "$CERT_PATH" ]]; then
    log_error "Cloudflare origin certificate not found at: $CERT_PATH"
    exit 1
fi

if [[ ! -f "$KEY_PATH" ]]; then
    log_error "Cloudflare origin key not found at: $KEY_PATH"
    exit 1
fi

chmod 600 "$KEY_PATH"
```

In Cloudflare mode, the script does not obtain a certificate — the operator must place it on the server manually before running `nginx.sh`. The script validates that both the certificate (`.crt`) and the private key (`.key`) exist at the expected paths. If either is missing, it exits with a descriptive error pointing to the Cloudflare dashboard.

The key file is set to `600` (owner-only read/write) regardless of how it was placed there. This is a security requirement — private keys with group or world read permissions would be rejected by many tools and represent a security risk.

**Where to get the Cloudflare origin certificate:**
> Cloudflare Dashboard → SSL/TLS → Origin Server → Create Certificate

Download the PEM-format certificate and key, place them at:
- `/etc/ssl/certs/<nginx_config_name>.crt`
- `/etc/ssl/private/<nginx_config_name>.key`

#### Certbot mode

```bash
apt-get install -y -qq certbot python3-certbot-nginx

certbot --nginx \
    --non-interactive \
    --agree-tos \
    --email "$CERTBOT_EMAIL" \
    -d "$DOMAIN"

certbot renew --dry-run --quiet
```

In Certbot mode, the script installs Certbot if it's not present, then runs it with `--nginx` and `--non-interactive` flags. The `--nginx` plugin modifies the generated Nginx config to add the correct `ssl_certificate` and `ssl_certificate_key` directives pointing to Let's Encrypt's managed paths.

After obtaining the certificate, the script runs `certbot renew --dry-run` to confirm that auto-renewal is properly configured. This is a dry run — it tests the renewal process without actually modifying any certificates.

---

### Step 4 — Configuration test and reload

```bash
nginx -t
systemctl reload nginx
```

`nginx -t` parses the entire Nginx configuration — not just the new file, but every enabled site and the main config. If there is a syntax error anywhere, it exits with a non-zero code and prints the error. Because `set -e` is active, a failed `nginx -t` stops the script immediately before `reload` is called.

`systemctl reload nginx` sends `SIGHUP` to the Nginx master process, which causes it to re-read its configuration and gracefully replace worker processes. Unlike `restart`, a reload does not drop active connections — requests in progress are served by the old workers until they finish.

After the reload, the script confirms Nginx is still running:

```bash
systemctl is-active nginx && log_success "Nginx is running" || {
    log_error "Nginx is not running after reload"
    exit 1
}
```

---

## The Generated Config

A config generated for `domain: api.yourdomain.com`, `port: 8000`, `ssl_mode: cloudflare` looks like:

```nginx
# Generated by nginx.sh on 2025-09-01 14:25:00
# Domain : api.yourdomain.com
# Backend: localhost:8000
# SSL    : cloudflare

server {
    listen 80;
    server_name api.yourdomain.com;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name api.yourdomain.com;

    ssl_certificate     /etc/ssl/certs/digit-api.crt;
    ssl_certificate_key /etc/ssl/private/digit-api.key;

    ssl_protocols             TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers               'ECDH+AESGCM:ECDH+AES256:ECDH+AES128:!aNULL:!MD5:!DSS';
    ssl_session_cache         shared:SSL:10m;
    ssl_session_timeout       10m;

    add_header X-Frame-Options      "SAMEORIGIN"    always;
    add_header X-Content-Type-Options "nosniff"     always;
    add_header X-XSS-Protection     "1; mode=block" always;
    add_header Referrer-Policy      "no-referrer"   always;

    access_log /var/log/nginx/digit-api.access.log;
    error_log  /var/log/nginx/digit-api.error.log;

    location / {
        proxy_pass         http://localhost:8000;
        proxy_http_version 1.1;

        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_connect_timeout 10s;
        proxy_read_timeout    30s;
        proxy_send_timeout    10s;
    }
}
```

---

*→ Next: [07 · deploy.sh](../07-deploy/deploy-script.md)*
