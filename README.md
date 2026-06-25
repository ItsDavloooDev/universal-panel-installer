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
- Built-in post-install checklist so you never miss a step.
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
  9) Post-install checklist
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

## Important notes

- The script delegates to upstream installers and repositories whenever possible.
- Always replace placeholder credentials before production use.
- Always put public services behind HTTPS.
- Test every component before moving live traffic.

## Upstream projects

| Project | Link |
|---|---|
| Pterodactyl Installer | https://github.com/pterodactyl-installer/pterodactyl-installer |
| Reviactyl | https://reviactyl.app/ |
| Pyrodactyl | https://pyrodactyl.dev/ |
| Wings documentation | https://pterodactyl.io/wings/1.0/installing.html |

## License

This project is provided as-is. Review and adapt it to your infrastructure before production use.
