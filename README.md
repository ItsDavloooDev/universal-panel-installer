# Universal Panel Installer

Interactive Bash installer for the most common Pterodactyl ecosystem setups.

Inspired by the popular [pterodactyl-installer](https://github.com/pterodactyl-installer/pterodactyl-installer) community project, this script lets you choose between multiple installation paths from a single interactive menu.

## Quick start

Clone the repository and run the installer as root:

```bash
git clone https://github.com/ItsDavloooDev/universal-panel-installer.git
cd universal-panel-installer
sudo bash install.sh
```

Or run it directly without cloning:

```bash
sudo bash <(curl -s https://raw.githubusercontent.com/ItsDavloooDev/universal-panel-installer/main/install.sh)
```

## Features

- Install **Pterodactyl Panel** natively on the host machine.
- Generate a **Dockerized Pterodactyl Panel** stack with MariaDB, Redis and Nginx.
- Install **Wings**.
- Install **Pterodactyl Panel + Wings** in one go.
- Install **Reviactyl**.
- Install **Reviactyl + Wings**.
- Prepare **Pyrodactyl** by cloning its repository.
- Prepare **Pyrodactyl + Wings**.
- Prepare **Pyrodactyl + Elytra**.
- Install **[Blueprint](https://blueprint.zip/)** extension framework on a native Pterodactyl panel.
- Built-in system diagnostics & health check with auto-fix for common issues.
- Execution log saved automatically in `logs/`.

## Supported systems

- Ubuntu
- Debian

Other distributions may work but are not officially targeted.

## Menu options

Once the script starts you will see this menu:

```
   1) Pterodactyl panel
   2) Wings
   3) Pterodactyl panel + Wings
   4) Reviactyl
   5) Reviactyl + Wings
   6) Pyrodactyl
   7) Pyrodactyl + Wings
   8) Pyrodactyl + Elytra
  10) Blueprint  (native panel only)

   9) System diagnostics & health check
   0) Exit
```

### Panel installation mode

When you pick a panel-related option, you will be asked whether you want:

- **Native** — delegates to the upstream community installer on the bare host.
- **Dockerized** — generates a ready-to-edit `docker-compose.yml` with MariaDB, Redis, the panel image and Nginx inside the directory you choose.

## Before you start

Make sure you have:

- A fresh server or VM running Ubuntu or Debian.
- Root access.
- A domain or subdomain already pointing to the machine (for SSL).
- Basic knowledge of reverse proxies and firewall rules.

## Setup flow

### Pterodactyl Panel

Prepare before running:

- Panel domain (e.g. `panel.example.com`)
- Mail SMTP credentials
- Database name, user and password
- SSL strategy: Nginx Proxy Manager, Traefik, Certbot or Cloudflare Tunnel

After the installation:

1. Complete panel environment configuration.
2. Run database migrations if required.
3. Create the first admin account.
4. Set up the cron job and queue worker.
5. Put the panel behind HTTPS.

### Wings

Prepare before running:

- Node hostname or subdomain
- Docker installed on the node (the script handles this)
- Game server port range

After the installation:

1. Create the node inside the panel.
2. Copy the generated config to `/etc/pterodactyl/config.yml`.
3. Enable and start Wings: `systemctl enable --now wings`
4. Test node connectivity from the panel.

### Reviactyl

Prepare before running:

- Pterodactyl panel URL
- Panel API key

After the installation:

1. Put Reviactyl behind a reverse proxy with HTTPS.
2. Create the admin account.
3. Connect your Pterodactyl instance.
4. Test the client area and billing flows.

### Pyrodactyl

The script clones the repository into the directory you choose.

After cloning:

1. Copy `.env.example` to `.env`.
2. Fill in database, Redis, panel URL and API credentials.
3. Deploy following the [Pyrodactyl documentation](https://pyrodactyl.dev/).
4. Put it behind a reverse proxy.

### Elytra

The script clones the repository into the directory you choose.

After cloning:

1. Copy `.env.example` to `.env`.
2. Fill in auth, public URL and panel connection details.
3. Start the application using the upstream instructions.
4. Test login, API responses and dashboard rendering.

### Blueprint

> **Requires a native Pterodactyl panel.**
> Blueprint is **not compatible** with the Dockerized panel, Reviactyl or Pyrodactyl.

[Blueprint](https://blueprint.zip/) is an extension framework for Pterodactyl that lets you install `.blueprint` extension packages directly from the admin area without touching the codebase manually.

Prepare before running:

- A working native Pterodactyl panel already installed (option `1` or `3` of this script, native mode).
- The panel directory on disk (default: `/var/www/pterodactyl`).
- Root access to the server.

The installer will:

1. Verify that the panel directory exists.
2. Download and run the official Blueprint installer from [get.blueprint.zip](https://get.blueprint.zip).
3. Track the installation path in the internal state file.

After the installation:

1. Log into your panel as an administrator.
2. Navigate to **Admin → Blueprint**.
3. Upload a `.blueprint` extension file to install it.
4. Extensions are applied automatically — no manual file editing required.

To check the installed Blueprint version and extension count at any time, run option `9` (System diagnostics) from the main menu.

## Dockerized panel — extra steps

When you choose the dockerized mode the script generates:

```
/your-chosen-dir/
├── docker-compose.yml
├── nginx/conf.d/panel.conf
├── panel/var/
├── mariadb/
└── redis/
```

Before starting the stack:

1. Open `docker-compose.yml` and replace every `change_me_*` placeholder with a strong value.
2. Generate `APP_KEY` with `php artisan key:generate --show` or use the panel docs method.
3. Add your SSL setup (Nginx Proxy Manager, Traefik or Certbot reverse proxy in front of Nginx).
4. Configure mail environment variables.
5. Start with: `docker compose up -d`

## System diagnostics

Option `9` runs a full health check on everything this script has installed:

- System resources (RAM, disk space)
- Docker daemon and Compose availability
- Panel service status (native or Docker containers)
- Wings service or container status and config validity
- Blueprint version and extension count
- Reviactyl, Pyrodactyl and Elytra repository and env status

If problems are detected, the script offers to auto-fix common issues (start stopped containers, restart services, etc.).

## Important notes

- The script delegates to upstream installers and repositories whenever possible.
- Always replace placeholder credentials before production use.
- Always put public services behind HTTPS.
- Test every component before moving live traffic.
- Blueprint only works on a **native** Pterodactyl panel — do not attempt to use it on a Dockerized panel.

## Upstream projects

| Project | Link |
|---|---|
| Pterodactyl Installer | https://github.com/pterodactyl-installer/pterodactyl-installer |
| Reviactyl | https://reviactyl.app/ |
| Pyrodactyl | https://pyrodactyl.dev/ |
| Blueprint | https://blueprint.zip/ |
| Wings documentation | https://pterodactyl.io/wings/1.0/installing.html |

## License

This project is provided as-is. Review and adapt it to your infrastructure before production use.
