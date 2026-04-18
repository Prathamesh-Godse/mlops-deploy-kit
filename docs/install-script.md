# 04 · install.sh

*← [Index](../../INDEX.md) · [utils.sh](../03-utils/utils-reference.md)*

---

## Purpose

`install.sh` sets up all system-level dependencies on a bare Ubuntu 24.04 LTS server. It installs Docker and Nginx from their official sources, adds the deployment user to the Docker group, and configures UFW with the correct firewall rules.

It is called by `deploy.sh` during Phase 1, or it can be run independently when only system setup is needed.

---

## Usage

```bash
sudo ./scripts/install.sh config.yaml
```

Requires root. Called with `sudo` when invoked by `deploy.sh`.

---

## Idempotency

The most important property of `install.sh` is that it is safe to run multiple times on the same server. Before installing any component, it checks whether that component is already present:

```bash
if command -v docker &>/dev/null; then
    log_warn "Docker already installed: $(docker --version)"
else
    # ... installation steps
fi
```

This means:
- Running `deploy.sh` on a server that already has Docker does not reinstall Docker
- Running `install.sh` twice produces no errors and no unintended side effects
- If a previous installation was interrupted partway through, re-running it picks up where it left off (for the components that weren't finished)

---

## Step-by-Step Walkthrough

### Step 1 — Package index update

```bash
apt-get update -qq
```

`-qq` suppresses all output except errors. Always run before any `apt-get install` to ensure the local package cache reflects the current state of the repositories.

---

### Step 2 — Docker installation

Docker is not in Ubuntu's default repositories. It must be installed from Docker's official repository, which requires:

1. Installing the tools needed to handle HTTPS repositories (`ca-certificates`, `curl`, `gnupg`, `lsb-release`)
2. Downloading and storing Docker's GPG key to `/etc/apt/keyrings/docker.gpg`
3. Adding Docker's APT repository entry to `/etc/apt/sources.list.d/docker.list`
4. Running `apt-get update` again to pick up the new repository
5. Installing `docker-ce`, `docker-ce-cli`, `containerd.io`, and `docker-buildx-plugin`

The GPG key step is critical for security — it ensures that packages downloaded from Docker's repository are verified against Docker's public key, preventing package substitution attacks.

```bash
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
```

After installation, Docker is enabled and started via systemd:

```bash
systemctl enable --now docker
```

`--now` both enables the service (so it starts on reboot) and starts it immediately in a single command.

---

### Step 3 — Docker group

Running Docker commands requires either root or membership in the `docker` group. The script identifies the real (non-root) user — the one that invoked `sudo` — via `$SUDO_USER`:

```bash
REAL_USER="${SUDO_USER:-$USER}"
usermod -aG docker "$REAL_USER"
```

`$SUDO_USER` is set by sudo to the original user. If the script is run as root directly (not via sudo), it falls back to `$USER`.

The group membership does not take effect in the current shell session. The user needs to log out and log back in, or run `newgrp docker` to activate it in the current session. The script logs this warning explicitly.

---

### Step 4 — Nginx installation

```bash
apt-get install -y -qq nginx
systemctl enable --now nginx
```

Nginx is available in Ubuntu's default repositories, so no additional repository setup is needed. `-y` confirms the install non-interactively. After installation, Nginx is enabled and started.

---

### Step 5 — UFW firewall configuration

UFW (Uncomplicated Firewall) is Ubuntu's front-end for `iptables`. The script configures three rules:

```bash
ufw allow OpenSSH          # SSH access — critical, must be first
ufw allow 'Nginx Full'     # Ports 80 and 443
ufw --force enable         # Activate UFW non-interactively
```

`OpenSSH` is allowed **before** enabling the firewall. Enabling UFW with no SSH rule would lock out the current SSH session — an irreversible mistake on a remote server. The script sets this rule first, every time, regardless of whether UFW was already active.

`Nginx Full` is a UFW application profile that opens both port 80 (HTTP) and port 443 (HTTPS).

Port 8000 is **intentionally not opened**. Docker is bound to `localhost:8000` — it is only reachable from the server itself (by Nginx). UFW would not affect the loopback interface anyway, but the explicit omission signals intent.

`--force` suppresses UFW's interactive confirmation prompt, making it safe to run in non-interactive scripts.

---

## What It Does Not Do

`install.sh` does not:
- Clone the project repository (done manually or via CI before running deploy.sh)
- Configure any SSL certificates (handled by nginx.sh)
- Build or run any Docker containers (handled by docker.sh)
- Write any Nginx configuration (handled by nginx.sh)

Its scope is strictly system-level prerequisites.

---

## Reading the Output

A successful run produces output like:

```
══════════════════════════════════════════
  ▶  Starting system installation
══════════════════════════════════════════
[INFO]  2025-09-01 14:20:00 — Config: config.yaml
[OK]    2025-09-01 14:20:02 — Package index updated

══════════════════════════════════════════
  ▶  Installing Docker
══════════════════════════════════════════
[WARN]  2025-09-01 14:20:03 — Docker already installed: Docker version 26.1.3

══════════════════════════════════════════
  ▶  Configuring Docker group
══════════════════════════════════════════
[WARN]  2025-09-01 14:20:03 — User 'ubuntu' is already in the docker group

══════════════════════════════════════════
  ▶  Installing Nginx
══════════════════════════════════════════
[WARN]  2025-09-01 14:20:04 — Nginx already installed: nginx/1.24.0

══════════════════════════════════════════
  ▶  Configuring UFW firewall
══════════════════════════════════════════
[OK]    2025-09-01 14:20:05 — UFW: OpenSSH allowed
[OK]    2025-09-01 14:20:05 — UFW: Nginx Full (80/443) allowed
[OK]    2025-09-01 14:20:05 — UFW enabled

[OK]    2025-09-01 14:20:05 — System installation complete
```

`[WARN]` lines for already-installed components are expected and correct on a pre-configured server. They indicate that the script detected existing state and skipped gracefully.

---

*→ Next: [05 · docker.sh](../05-docker/docker-script.md)*
