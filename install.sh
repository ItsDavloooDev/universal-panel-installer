#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_VERSION="1.0.0"
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${BASE_DIR}/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/install-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

export DEBIAN_FRONTEND=noninteractive

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

PANEL_INSTALLER_URL="https://raw.githubusercontent.com/pterodactyl-installer/pterodactyl-installer/master/install.sh"
REVIACTYL_INSTALLER_URL="https://raw.githubusercontent.com/reviactyl/reviactyl/main/install.sh"
PYRODACTYL_REPO_URL="https://github.com/pyrohost/pyrodactyl"
ELYTRA_REPO_URL="https://github.com/pyrohost/elytra"
DOCKER_SCRIPT_URL="https://get.docker.com"
COMPOSE_BIN="/usr/local/bin/docker-compose"

trap 'echo -e "${RED}[ERROR]${NC} Command failed on line $LINENO. Check ${LOG_FILE}"' ERR

print_banner() {
  clear || true
  cat <<'BANNER'
██████╗ ███████╗███████╗██████╗  ██████╗     ███████╗██╗   ██╗██╗███████╗███████╗
██╔══██╗╚══██╔══╝██╔════╝██╔══██╗██╔═══██╗    ██╔════╝██║   ██║██║╚══██╔══╝██╔════╝
██████╔╝   ██║   █████╗  ██████╔╝██║   ██║    █████╗  ██║   ██║██║   ██║   █████╗
██╔═══╝    ██║   ██╔══╝  ██╔══██╗██║   ██║    ╚═══██╗██║   ██║██║   ██║   ██╔══╝
██║        ██║   ███████╗██║  ██║╚██████╔╝    ███████║╚██████╔╝██║   ██║   ███████╗
╚═╝        ╚═╝   ╚══════╝╚═╝  ╚═╝ ╚═════╝     ╚══════╝ ╚═════╝ ╚═╝   ╚═╝   ╚══════╝
BANNER
  echo
  echo -e "${CYAN}Universal Panel Installer v${SCRIPT_VERSION}${NC}"
  echo -e "${CYAN}Log file:${NC} ${LOG_FILE}"
  echo
}

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }

require_root() {
  if [[ ${EUID} -ne 0 ]]; then
    error "Run this script as root. Example: sudo bash install.sh"
    exit 1
  fi
}

pause() {
  read -r -p "Press Enter to continue..." _
}

ask_input() {
  local prompt="$1"
  local default_value="${2:-}"
  local value
  if [[ -n "$default_value" ]]; then
    read -r -p "$prompt [$default_value]: " value
    echo "${value:-$default_value}"
  else
    read -r -p "$prompt: " value
    echo "$value"
  fi
}

ask_yes_no() {
  local prompt="$1"
  local default_answer="${2:-y}"
  local answer
  local suffix="[Y/n]"
  [[ "$default_answer" == "n" ]] && suffix="[y/N]"
  while true; do
    read -r -p "$prompt $suffix: " answer
    answer="${answer:-$default_answer}"
    case "$answer" in
      y|Y|yes|YES) return 0 ;;
      n|N|no|NO)   return 1 ;;
      *) warn "Please answer yes or no." ;;
    esac
  done
}

select_option() {
  local title="$1"
  shift
  local options=("$@")
  echo "$title"
  local i=1
  for option in "${options[@]}"; do
    echo "  $i) $option"
    ((i++))
  done
  local choice
  while true; do
    read -r -p "Choose an option [1-${#options[@]}]: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options[@]} )); then
      echo "$choice"
      return 0
    fi
    warn "Invalid choice."
  done
}

ensure_supported_os() {
  [[ -f /etc/os-release ]] || { error "Unsupported system: /etc/os-release not found"; exit 1; }
  . /etc/os-release
  info "Detected OS: ${PRETTY_NAME:-Unknown Linux}"
  case "${ID:-}" in
    ubuntu|debian)
      success "Supported distribution detected."
      ;;
    *)
      warn "This script is optimized for Ubuntu and Debian. Continuing may fail."
      ask_yes_no "Continue on unsupported distro?" "n" || exit 1
      ;;
  esac
}

install_base_packages() {
  info "Installing base dependencies..."
  apt-get update -y
  apt-get upgrade -y
  apt-get install -y curl wget git jq ca-certificates lsb-release gnupg \
    apt-transport-https software-properties-common unzip tar ufw sudo bash-completion
  success "Base dependencies installed."
}

configure_firewall_panel() {
  if ask_yes_no "Configure UFW rules for the panel (22, 80, 443, 8080)?" "y"; then
    ufw allow 22/tcp   || true
    ufw allow 80/tcp   || true
    ufw allow 443/tcp  || true
    ufw allow 8080/tcp || true
    if ask_yes_no "Enable UFW now?" "n"; then ufw --force enable; fi
    success "Firewall rules applied for the panel."
  fi
}

configure_firewall_wings() {
  if ask_yes_no "Configure UFW rules for Wings (22, 8080, 2022)?" "y"; then
    ufw allow 22/tcp   || true
    ufw allow 8080/tcp || true
    ufw allow 2022/tcp || true
    if ask_yes_no "Enable UFW now?" "n"; then ufw --force enable; fi
    success "Firewall rules applied for Wings."
  fi
}

install_docker_engine() {
  if command -v docker >/dev/null 2>&1; then
    success "Docker is already installed."
  else
    info "Installing Docker using the official convenience script..."
    curl -fsSL "$DOCKER_SCRIPT_URL" | sh
    systemctl enable --now docker
    success "Docker installed and started."
  fi

  if docker compose version >/dev/null 2>&1; then
    success "Docker Compose plugin is already available."
  else
    info "Installing Docker Compose plugin..."
    apt-get install -y docker-compose-plugin || true
    if ! docker compose version >/dev/null 2>&1; then
      warn "Plugin not found, installing standalone docker-compose binary..."
      curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
        -o "$COMPOSE_BIN"
      chmod +x "$COMPOSE_BIN"
      success "Standalone docker-compose installed at $COMPOSE_BIN"
    fi
  fi
}

ensure_git_repo_cloned_or_updated() {
  local repo_url="$1"
  local target_dir="$2"
  if [[ -d "$target_dir/.git" ]]; then
    info "Updating existing repository in $target_dir"
    git -C "$target_dir" pull --ff-only
  else
    info "Cloning $repo_url into $target_dir"
    git clone "$repo_url" "$target_dir"
  fi
}

run_remote_installer() {
  local url="$1"
  local label="$2"
  info "Downloading and executing $label installer..."
  bash <(curl -s "$url")
}

install_pterodactyl_native() {
  info "Starting native Pterodactyl panel installer..."
  warn "The upstream installer will ask for panel, web server, database and SSL details."
  configure_firewall_panel
  run_remote_installer "$PANEL_INSTALLER_URL" "Pterodactyl"
  success "Native Pterodactyl installer finished."
}

write_docker_compose_pterodactyl() {
  local stack_dir="$1"
  local panel_domain="$2"
  local timezone="$3"

  mkdir -p "$stack_dir/nginx/conf.d" "$stack_dir/panel/var" "$stack_dir/mariadb" "$stack_dir/redis"

  cat > "$stack_dir/docker-compose.yml" <<COMPOSE
services:
  mariadb:
    image: mariadb:11
    container_name: ptero-mariadb
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: change_me_root_password
      MYSQL_DATABASE: panel
      MYSQL_USER: pterodactyl
      MYSQL_PASSWORD: change_me_panel_password
      TZ: ${timezone}
    volumes:
      - ./mariadb:/var/lib/mysql

  redis:
    image: redis:7-alpine
    container_name: ptero-redis
    restart: unless-stopped
    command: ["redis-server", "--appendonly", "yes"]
    volumes:
      - ./redis:/data

  panel:
    image: ghcr.io/pterodactyl/panel:latest
    container_name: ptero-panel
    restart: unless-stopped
    depends_on:
      - mariadb
      - redis
    environment:
      APP_URL: https://${panel_domain}
      APP_TIMEZONE: ${timezone}
      DB_HOST: mariadb
      DB_PORT: 3306
      DB_DATABASE: panel
      DB_USERNAME: pterodactyl
      DB_PASSWORD: change_me_panel_password
      REDIS_HOST: redis
      CACHE_DRIVER: redis
      SESSION_DRIVER: redis
      QUEUE_CONNECTION: redis
      APP_ENV: production
      APP_DEBUG: "false"
      APP_KEY: base64:generate_me_with_artisan_or_panel_docs
    volumes:
      - ./panel/var:/app/var

  nginx:
    image: nginx:stable-alpine
    container_name: ptero-nginx
    restart: unless-stopped
    depends_on:
      - panel
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d
COMPOSE

  cat > "$stack_dir/nginx/conf.d/panel.conf" <<NGINX
server {
    listen 80;
    server_name ${panel_domain};

    location / {
        proxy_pass http://panel:80;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
NGINX

  success "Docker Compose files written to $stack_dir"
}

install_pterodactyl_docker() {
  local stack_dir panel_domain timezone
  stack_dir="$(ask_input 'Docker stack directory' '/opt/pterodactyl-docker')"
  panel_domain="$(ask_input 'Panel domain' 'panel.example.com')"
  timezone="$(ask_input 'Timezone' 'UTC')"
  install_docker_engine
  configure_firewall_panel
  write_docker_compose_pterodactyl "$stack_dir" "$panel_domain" "$timezone"
  echo
  echo "Next steps:"
  echo "1. Edit $stack_dir/docker-compose.yml and replace every change_me_* value."
  echo "2. Add SSL, mail settings and a valid APP_KEY before production use."
  echo "3. Start the stack with: cd $stack_dir && docker compose up -d"
  echo "4. Complete panel setup following the official documentation."
}

install_wings() {
  info "Starting Wings installer..."
  install_docker_engine
  configure_firewall_wings
  run_remote_installer "$PANEL_INSTALLER_URL" "Pterodactyl / Wings"
  success "Wings installer finished."
}

install_reviactyl() {
  info "Starting Reviactyl installer..."
  warn "Keep your panel URL and API credentials ready before continuing."
  run_remote_installer "$REVIACTYL_INSTALLER_URL" "Reviactyl"
  success "Reviactyl installer finished."
}

install_pyrodactyl() {
  local target_dir
  target_dir="$(ask_input 'Pyrodactyl install directory' '/opt/pyrodactyl')"
  install_docker_engine
  ensure_git_repo_cloned_or_updated "$PYRODACTYL_REPO_URL" "$target_dir"
  echo
  echo "Pyrodactyl repository ready at $target_dir"
  echo "Copy the example env file, fill the values and deploy with the upstream method."
  success "Pyrodactyl source prepared."
}

install_elytra() {
  local target_dir
  target_dir="$(ask_input 'Elytra install directory' '/opt/elytra')"
  install_docker_engine
  ensure_git_repo_cloned_or_updated "$ELYTRA_REPO_URL" "$target_dir"
  echo
  echo "Elytra repository ready at $target_dir"
  echo "Copy the example env file, fill the values and deploy with the upstream method."
  success "Elytra source prepared."
}

show_setup_guides() {
  cat <<'GUIDE'

==================== POST-INSTALL CHECKLIST ====================

Pterodactyl panel
  - Point your domain DNS to the server IP.
  - Configure SSL with Cloudflare Tunnel, Nginx Proxy Manager, Traefik or Certbot.
  - Complete panel environment setup: queue worker, cron, mail settings.
  - Create the first admin user.
  - Create node allocations for every Wings node.

Wings
  - Create a node inside the panel.
  - Generate the node config from the panel and save it to /etc/pterodactyl/config.yml.
  - Start Wings: systemctl enable --now wings
  - Validate node connectivity from the panel.

Reviactyl
  - Prepare your panel URL and API key.
  - Complete the installer prompts.
  - Put it behind a reverse proxy with HTTPS.
  - Create the admin account and bind your Pterodactyl instance.

Pyrodactyl
  - Open the cloned repository directory.
  - Copy .env.example to .env and fill every required value.
  - Build or start the app following the upstream documentation.
  - Put it behind a reverse proxy and verify workers or webhooks if used.

Elytra
  - Open the cloned repository directory.
  - Copy .env.example to .env and fill auth, public URL and panel credentials.
  - Start the stack using the upstream instructions.
  - Test login, API calls and dashboard rendering.

Useful links
  Pterodactyl installer : https://github.com/pterodactyl-installer/pterodactyl-installer
  Reviactyl             : https://reviactyl.app/
  Pyrodactyl            : https://pyrodactyl.dev/
  Wings docs            : https://pterodactyl.io/wings/1.0/installing.html

================================================================
GUIDE
}

choose_panel_mode() {
  local mode
  mode=$(select_option "How do you want to install the Pterodactyl panel?" \
    "Native on the machine" \
    "Dockerized stack")
  case "$mode" in
    1) install_pterodactyl_native ;;
    2) install_pterodactyl_docker ;;
  esac
}

main_menu() {
  while true; do
    print_banner
    echo "What do you want to install?"
    echo
    echo "  1) Pterodactyl panel"
    echo "  2) Wings"
    echo "  3) Pterodactyl panel + Wings"
    echo "  4) Reviactyl"
    echo "  5) Reviactyl + Wings"
    echo "  6) Pyrodactyl"
    echo "  7) Pyrodactyl + Wings"
    echo "  8) Pyrodactyl + Elytra"
    echo "  9) Post-install checklist"
    echo "  0) Exit"
    echo
    read -r -p "Your choice: " choice
    case "$choice" in
      1) choose_panel_mode; pause ;;
      2) install_wings; pause ;;
      3) choose_panel_mode; install_wings; pause ;;
      4) install_reviactyl; pause ;;
      5) install_reviactyl; install_wings; pause ;;
      6) install_pyrodactyl; pause ;;
      7) install_pyrodactyl; install_wings; pause ;;
      8) install_pyrodactyl; install_elytra; pause ;;
      9) show_setup_guides; pause ;;
      0) success "Bye."; exit 0 ;;
      *) warn "Invalid choice, try again."; pause ;;
    esac
  done
}

require_root
ensure_supported_os
install_base_packages
main_menu
