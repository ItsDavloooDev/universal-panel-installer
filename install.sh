#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_VERSION="3.0.0"
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${BASE_DIR}/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/install-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

export DEBIAN_FRONTEND=noninteractive

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

# URLs
BLUEPRINT_INSTALLER_URL="https://get.blueprint.zip"
PYRODACTYL_REPO_URL="https://github.com/pyrohost/pyrodactyl"
ELYTRA_REPO_URL="https://github.com/pyrohost/elytra"
DOCKER_SCRIPT_URL="https://get.docker.com"
COMPOSE_BIN="/usr/local/bin/docker-compose"
STATE_FILE="/etc/universal-panel-installer/state.json"

mkdir -p /etc/universal-panel-installer
[[ -f "$STATE_FILE" ]] || echo '{}' > "$STATE_FILE"

trap 'echo -e "${RED}[ERROR]${NC} Script failed on line $LINENO — check ${LOG_FILE}"' ERR

print_banner() {
    clear || true
    echo -e "${CYAN}${BOLD}"
    cat <<'BANNER'
 ██╗   ██╗███╗   ██╗██╗██╗   ██╗███████╗██████╗ ███████╗ █████╗ ██╗
 ██║   ██║████╗  ██║██║██║   ██║██╔════╝██╔══██╗██╔════╝██╔══██╗██║
 ██║   ██║██╔██╗ ██║██║██║   ██║█████╗  ██████╔╝███████╗███████║██║
 ██║   ██║██║╚██╗██║██║╚██╗ ██╔╝██╔══╝  ██╔══██╗╚════██║██╔══██║██║
 ╚██████╔╝██║ ╚████║██║ ╚████╔╝ ███████╗██║  ██║███████║██║  ██║███████╗
  ╚═════╝ ╚═╝  ╚═══╝╚═╝  ╚═══╝  ╚══════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚══════╝
 ██████╗  █████╗ ███╗   ██╗███████╗██╗         ██╗███╗   ██╗███████╗███████���╗
 ██╔══██╗██╔══██╗████╗  ██║██╔════╝██║         ██║████╗  ██║██╔════╝╚══██╔══╝
 ██████╔╝███████║██╔██╗ ██║█████╗  ██║         ██║██╔██╗ ██║███████╗   ██║
 ██╔═══╝ ██╔══██║██║╚██╗██║██╔══╝  ██║         ██║██║╚██╗██║╚════██║   ██║
 ██║     ██║  ██║██║ ╚████║███████╗███████╗     ██║██║ ╚████║███████║   ██║
 ╚═╝     ╚═╝  ╚═╝╚═╝  ╚═══╝╚══════╝╚══════╝     ╚═╝╚═╝  ╚═══╝╚══════╝   ╚═╝
BANNER
    echo -e "${NC}"
    echo -e " ${CYAN}Universal Panel Installer${NC} ${BOLD}v${SCRIPT_VERSION}${NC}"
    echo -e " ${CYAN}Log:${NC} ${LOG_FILE}"
    echo
}

info() { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }
step() { echo -e "\n${MAGENTA}${BOLD}>>> $*${NC}"; }

require_root() {
    if [[ ${EUID} -ne 0 ]]; then
        error "Run this script as root: sudo bash install.sh"
        exit 1
    fi
}

pause() {
    echo
    read -r -p "Press Enter to return to the menu..." _
}

ask_input() {
    local prompt="$1" default_value="${2:-}" value
    if [[ -n "$default_value" ]]; then
        read -r -p " ${CYAN}?${NC} $prompt [${default_value}]: " value
        echo "${value:-$default_value}"
    else
        while true; do
            read -r -p " ${CYAN}?${NC} $prompt: " value
            [[ -n "$value" ]] && break
            warn "This field cannot be empty."
        done
        echo "$value"
    fi
}

ask_input_optional() {
    local prompt="$1" value
    read -r -p " ${CYAN}?${NC} $prompt (press Enter to skip): " value
    echo "$value"
}

ask_password() {
    local prompt="$1" value confirm
    while true; do
        read -r -s -p " ${CYAN}?${NC} $prompt: " value; echo
        [[ -n "$value" ]] && break
        warn "Password cannot be empty."
    done
    read -r -s -p " ${CYAN}?${NC} Confirm password: " confirm; echo
    if [[ "$value" != "$confirm" ]]; then
        warn "Passwords do not match, try again."
        ask_password "$prompt"
        return
    fi
    echo "$value"
}

ask_yes_no() {
    local prompt="$1" default_answer="${2:-y}" answer suffix="[Y/n]"
    [[ "$default_answer" == "n" ]] && suffix="[y/N]"
    while true; do
        read -r -p " ${CYAN}?${NC} $prompt $suffix: " answer
        answer="${answer:-$default_answer}"
        case "$answer" in
            y|Y|yes|YES) return 0 ;;
            n|N|no|NO) return 1 ;;
            *) warn "Please answer yes or no." ;;
        esac
    done
}

select_option() {
    local title="$1"; shift
    local options=("$@")
    echo -e " ${BOLD}$title${NC}"
    local i=1
    for o in "${options[@]}"; do
        echo " $i) $o"
        ((i++))
    done
    local choice
    while true; do
        read -r -p " Your choice [1-${#options[@]}]: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options[@]} )); then
            echo "$choice"; return 0
        fi
        warn "Invalid choice."
    done
}

generate_app_key() {
    python3 -c "import secrets,base64; print('base64:' + base64.b64encode(secrets.token_bytes(32)).decode())" 2>/dev/null \
        || openssl rand -base64 32 | awk '{print "base64:" $1}'
}

state_set() {
    local key="$1" val="$2"
    local tmp; tmp="$(mktemp)"
    jq --arg k "$key" --arg v "$val" '.[$k] = $v' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

state_get() {
    jq -r --arg k "$1" '.[$k] // empty' "$STATE_FILE"
}

ensure_supported_os() {
    [[ -f /etc/os-release ]] || { error "/etc/os-release not found"; exit 1; }
    . /etc/os-release
    info "Detected OS: ${PRETTY_NAME:-Unknown Linux}"
    case "${ID:-}" in
        ubuntu|debian) success "Supported distribution." ;;
        *)
            warn "This script is optimized for Ubuntu/Debian."
            ask_yes_no "Continue on unsupported distro?" "n" || exit 1
            ;;
    esac
}

install_base_packages() {
    info "Installing base dependencies..."
    apt-get update -y >/dev/null 2>&1
    apt-get upgrade -y >/dev/null 2>&1
    apt-get install -y curl wget git jq ca-certificates lsb-release gnupg \
        apt-transport-https software-properties-common unzip tar ufw sudo bash-completion python3 >/dev/null 2>&1
    success "Base dependencies installed."
}

configure_firewall_panel() {
    if ask_yes_no "Configure UFW firewall for the panel? (opens 22, 80, 443, 8080)" "y"; then
        ufw allow 22/tcp || true; ufw allow 80/tcp || true
        ufw allow 443/tcp || true; ufw allow 8080/tcp || true
        if ask_yes_no "Enable UFW now?" "n"; then ufw --force enable; fi
        success "Panel firewall rules applied."
    fi
}

configure_firewall_wings() {
    if ask_yes_no "Configure UFW firewall for Wings? (opens 22, 8080, 2022)" "y"; then
        ufw allow 22/tcp || true; ufw allow 8080/tcp || true; ufw allow 2022/tcp || true
        if ask_yes_no "Enable UFW now?" "n"; then ufw --force enable; fi
        success "Wings firewall rules applied."
    fi
}

install_docker_engine() {
    if command -v docker >/dev/null 2>&1; then
        success "Docker already installed: $(docker --version)"
    else
        info "Installing Docker via official script..."
        curl -fsSL "$DOCKER_SCRIPT_URL" | sh >/dev/null 2>&1
        systemctl enable --now docker
        success "Docker installed and started."
    fi
    if docker compose version >/dev/null 2>&1; then
        success "Docker Compose plugin available."
    else
        apt-get install -y docker-compose-plugin >/dev/null 2>&1 || true
        if ! docker compose version >/dev/null 2>&1; then
            curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
                -o "$COMPOSE_BIN" && chmod +x "$COMPOSE_BIN"
            success "Standalone docker-compose installed."
        fi
    fi
}

ensure_git_repo() {
    local url="$1" dir="$2"
    if [[ -d "$dir/.git" ]]; then
        info "Updating repo in $dir"
        git -C "$dir" pull --ff-only
    else
        info "Cloning $url into $dir"
        git clone "$url" "$dir"
    fi
}

ensure_supported_os() {
    [[ -f /etc/os-release ]] || { error "/etc/os-release not found"; exit 1; }
    . /etc/os-release
    info "Detected OS: ${PRETTY_NAME:-Unknown Linux}"
    case "${ID:-}" in
        ubuntu|debian) success "Supported distribution." ;;
        *)
            warn "This script is optimized for Ubuntu/Debian."
            ask_yes_no "Continue on unsupported distro?" "n" || exit 1
            ;;
    esac
}

install_base_packages() {
    info "Installing base dependencies..."
    apt-get update -y >/dev/null 2>&1
    apt-get upgrade -y >/dev/null 2>&1
    apt-get install -y curl wget git jq ca-certificates lsb-release gnupg \
        apt-transport-https software-properties-common unzip tar ufw sudo bash-completion python3 >/dev/null 2>&1
    success "Base dependencies installed."
}

# ============================================================================
# DOCKER PANEL CONFIG
# ============================================================================
collect_docker_panel_config() {
    step "Docker panel configuration"
    echo -e " ${YELLOW}Fill in every field — all values will be written directly into docker-compose.yml${NC}\n"
    PTERO_STACK_DIR="$(ask_input 'Stack directory on disk' '/opt/pterodactyl')"
    PTERO_DOMAIN="$(ask_input 'Panel domain (e.g. panel.example.com)')"
    PTERO_TIMEZONE="$(ask_input 'Server timezone' 'Europe/Rome')"
    step "Database credentials"
    PTERO_DB_NAME="$(ask_input 'Database name' 'panel')"
    PTERO_DB_USER="$(ask_input 'Database user' 'pterodactyl')"
    PTERO_DB_PASS="$(ask_password 'Database user password')"
    PTERO_DB_ROOT_PASS="$(ask_password 'MariaDB root password')"
    step "Application key"
    local generated_key; generated_key="$(generate_app_key)"
    info "Auto-generated APP_KEY: ${generated_key}"
    local custom_key
    custom_key="$(ask_input_optional 'Enter a custom APP_KEY or leave blank to use the generated one')"
    PTERO_APP_KEY="${custom_key:-$generated_key}"
    step "Mail configuration (optional — press Enter on each field to skip)"
    PTERO_MAIL_HOST="$(ask_input_optional 'SMTP host (e.g. smtp.gmail.com)')"
    PTERO_MAIL_PORT="$(ask_input_optional 'SMTP port (e.g. 587)')"
    PTERO_MAIL_USER="$(ask_input_optional 'SMTP username / email')"
    PTERO_MAIL_PASS=""
    if [[ -n "$PTERO_MAIL_HOST" ]]; then
        read -r -s -p " ${CYAN}?${NC} SMTP password (Enter to skip): " PTERO_MAIL_PASS; echo
    fi
    PTERO_MAIL_FROM="$(ask_input_optional 'From address (e.g. noreply@example.com)')"
    PTERO_MAIL_FROM_NAME="$(ask_input_optional 'From name (e.g. Pterodactyl)')"
    PTERO_MAIL_ENCRYPTION="$(ask_input_optional 'Encryption: tls or ssl (default: tls)')"
    PTERO_MAIL_ENCRYPTION="${PTERO_MAIL_ENCRYPTION:-tls}"
}

write_docker_compose_pterodactyl() {
    local d="$PTERO_STACK_DIR"
    mkdir -p "$d/nginx/conf.d" "$d/panel/var" "$d/mariadb" "$d/redis"
    local mail_env=""
    if [[ -n "$PTERO_MAIL_HOST" ]]; then
        mail_env=" MAIL_DRIVER: smtp
 MAIL_HOST: ${PTERO_MAIL_HOST}
 MAIL_PORT: ${PTERO_MAIL_PORT:-587}
 MAIL_USERNAME: ${PTERO_MAIL_USER}
 MAIL_PASSWORD: ${PTERO_MAIL_PASS}
 MAIL_ENCRYPTION: ${PTERO_MAIL_ENCRYPTION}
 MAIL_FROM: ${PTERO_MAIL_FROM}
 MAIL_FROM_NAME: ${PTERO_MAIL_FROM_NAME}"
    fi
    cat > "$d/docker-compose.yml" <<COMPOSE
services:
 mariadb:
  image: mariadb:11
  container_name: ptero-mariadb
  restart: unless-stopped
  environment:
   MYSQL_ROOT_PASSWORD: ${PTERO_DB_ROOT_PASS}
   MYSQL_DATABASE: ${PTERO_DB_NAME}
   MYSQL_USER: ${PTERO_DB_USER}
   MYSQL_PASSWORD: ${PTERO_DB_PASS}
   TZ: ${PTERO_TIMEZONE}
  volumes:
   - ./mariadb:/var/lib/mysql
 redis:
  image: redis:7-alpine
  container_name: ptero-redis
  restart: unless-stopped
  command: redis-server --appendonly yes
 redis:
  image: redis:7-alpine
  container_name: ptero-redis
  restart: unless-stopped
  command: redis-server --appendonly yes
 ptero-panel:
  image: ghcr.io/pterodactyl/panel:latest
  container_name: ptero-panel
  restart: unless-stopped
  environment:
   APP_URL: "https://${PTERO_DOMAIN}"
   TZ: ${PTERO_TIMEZONE}
   APP_KEY: "${PTERO_APP_KEY}"
   DB_HOST: mariadb
   DB_DATABASE: ${PTERO_DB_NAME}
   DB_USERNAME: ${PTERO_DB_USER}
   DB_PASSWORD: ${PTERO_DB_PASS}
${mail_env}
  volumes:
   - ./panel/var:/app/var
   - ./panel/storage:/app/storage
   - ./panel/logs:/app/storage/logs
  depends_on:
   - mariadb
   - redis
 nginx:
  image: nginx:alpine
  container_name: ptero-nginx
  restart: unless-stopped
  depends_on:
   - ptero-panel
  ports:
   - "80:80"
   - "443:443"
  volumes:
   - ./nginx/conf.d:/etc/nginx/conf.d
COMPOSE
    cat > "$d/nginx/conf.d/panel.conf" <<NGINX
server {
 listen 80;
 server_name ${PTERO_DOMAIN};
 location / {
  proxy_pass http://ptero-panel:80;
  proxy_set_header Host \$host;
  proxy_set_header X-Real-IP \$remote_addr;
  proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
  proxy_set_header X-Forwarded-Proto \$scheme;
 }
}
NGINX
    state_set "docker_panel_dir" "$d"
    state_set "docker_panel_domain" "$PTERO_DOMAIN"
    success "All panel files written to $d"
    echo
    info "Start the stack with:"
    echo " cd $d && docker compose up -d"
}

write_docker_compose_wings() {
    local d="$WINGS_STACK_DIR"
    mkdir -p "$d/wings/etc" "$d/wings/tmp"
    cat > "$d/wings-compose.yml" <<COMPOSE
services:
 wings:
  image: ghcr.io/pterodactyl/wings:latest
  container_name: ptero-wings
  restart: unless-stopped
  network_mode: host
  privileged: true
  environment:
   TZ: ${WINGS_TIMEZONE}
  volumes:
   - /var/run/docker.sock:/var/run/docker.sock
   - /var/lib/docker/containers:/var/lib/docker/containers
   - ./wings/etc:/etc/pterodactyl
   - ./wings/tmp:/tmp/pterodactyl
   - /tmp/pterodactyl:/tmp/pterodactyl
COMPOSE
    mkdir -p "$d/wings/etc"
    cat > "$d/wings/etc/config.yml" <<WINGSCFG
debug: false
uuid: ${WINGS_NODE_UUID}
token_id: ${WINGS_TOKEN_ID}
token: ${WINGS_TOKEN}
api:
 host: 0.0.0.0
 port: 8080
 ssl:
  enabled: false
 upload_limit: 100
system:
 data: /var/lib/pterodactyl/volumes
 sftp:
  bind_port: 2022
remote: ${WINGS_PANEL_URL}
allowed_mounts: []
WINGSCFG
    state_set "wings_docker_dir" "$d"
    success "Wings Docker files written to $d"
    echo
    info "Start Wings with:"
    echo " cd $d && docker compose -f wings-compose.yml up -d"
}

# ============================================================================
# PTERODACTYL PANEL — NATIVE
# ============================================================================
install_pterodactyl_native() {
    step "Pterodactyl Panel — Native Installation"
    echo
    echo -e " ${YELLOW}This will install Pterodactyl Panel natively on this machine.${NC}"
    echo -e " ${YELLOW}The script will ask you for web server, DB, SSL and SMTP settings.${NC}\n"

    configure_firewall_panel

    # Install dependencies
    info "Installing Pterodactyl dependencies..."
    apt-get update -y >/dev/null 2>&1
    LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php >/dev/null 2>&1 || true
    curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg 2>/dev/null || true
    echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/redis.list >/dev/null 2>&1 || true
    apt-get update -y >/dev/null 2>&1
    apt-get install -y php8.3 php8.3-common php8.3-cli php8.3-gd php8.3-mysql php8.3-mbstring php8.3-bcmath php8.3-xml php8.3-fpm php8.3-curl php8.3-zip mariadb-server nginx tar unzip git redis-server >/dev/null 2>&1
    success "Dependencies installed."

    info "Installing Composer..."
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer >/dev/null 2>&1
    success "Composer installed."

    # Create directory
    local panel_dir="/var/www/pterodactyl"
    mkdir -p "$panel_dir"
    cd "$panel_dir"

    # Download panel
    info "Downloading Pterodactyl panel..."
    curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz >/dev/null 2>&1
    tar -xzvf panel.tar.gz >/dev/null 2>&1
    chmod -R 755 storage/* bootstrap/cache/
    success "Panel files downloaded."

    # Database setup
    step "Database setup"
    local db_pass; db_pass="$(ask_password 'Database password for pterodactyl user')"
    local db_root_pass; db_root_pass="$(ask_password 'MariaDB root password')"

    mariadb -u root -e "CREATE DATABASE IF NOT EXISTS panel; CREATE USER IF NOT EXISTS 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '${db_pass}'; GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION; FLUSH PRIVILEGES;"
    success "Database created."

    # Environment setup
    cp .env.example .env
    COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader >/dev/null 2>&1
    php artisan key:generate --force

    # Environment setup
    info "Running environment setup wizard..."
    php artisan p:environment:setup
    php artisan p:environment:database
    php artisan p:environment:mail

    # Database migration
    info "Running database migrations..."
    php artisan migrate --seed --force >/dev/null 2>&1
    success "Database migrated."

    # Create admin user
    step "Create admin user"
    local admin_email admin_user admin_pass admin_first admin_last
    admin_email="$(ask_input 'Admin email')"
    admin_user="$(ask_input 'Admin username')"
    admin_pass="$(ask_password 'Admin password')"
    admin_first="$(ask_input 'Admin first name' 'Admin')"
    admin_last="$(ask_input 'Admin last name' 'User')"

    php artisan p:user:make --email="$admin_email" --username="$admin_user" --name-first="$admin_first" --name-last="$admin_last" --password="$admin_pass" --admin=1
    success "Admin user created."

    # Permissions
    chown -R www-data:www-data "$panel_dir"/*

    # Cron
    (crontab -l 2>/dev/null | grep -v 'artisan schedule:run'; echo "* * * * * php ${panel_dir}/artisan schedule:run >> /dev/null 2>&1") | crontab -
    success "Cron configured."

    # Queue worker
    cat > /etc/systemd/system/pteroq.service <<SYSTEMD
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service

[Service]
User=www-data
Group=www-data
Restart=on-failure
StartLimitInterval=600
StartLimitBurst=10
WorkingDirectory=${panel_dir}
ExecStart=/usr/bin/php ${panel_dir}/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
SYSTEMD
    systemctl daemon-reload
    systemctl enable --now redis-server pteroq >/dev/null 2>&1
    success "Queue worker configured."

    state_set "pterodactyl_native" "installed"
    state_set "install_mode" "native"
    state_set "pterodactyl_dir" "$panel_dir"
    success "Native Pterodactyl panel installation complete."
}

install_pterodactyl_docker() {
    collect_docker_panel_config
    install_docker_engine
    configure_firewall_panel
    write_docker_compose_pterodactyl
    state_set "pterodactyl_docker" "installed"
    state_set "install_mode" "docker"
}

choose_panel_mode() {
    local mode
    mode=$(select_option "How do you want to install the Pterodactyl panel?" \
        "Native on the machine" \
        "Dockerized stack (fully configured by this script)")
    case "$mode" in
        1) install_pterodactyl_native ;;
        2) install_pterodactyl_docker ;;
    esac
}

# ============================================================================
# WINGS — NATIVE (via upstream installer)
# ============================================================================
install_wings_native() {
    step "Wings — Native Installation"
    echo
    echo -e " ${YELLOW}Installing Wings via the official upstream installer.${NC}"
    echo -e " ${YELLOW}You will be guided through node configuration.${NC}\n"

    configure_firewall_wings
    install_docker_engine

    # Run the upstream wings installer (option 2 = wings only)
    bash <(curl -s https://raw.githubusercontent.com/pterodactyl-installer/pterodactyl-installer/master/install.sh) <<< "2"

    state_set "wings" "installed"
    state_set "wings_mode" "native"
    success "Wings native installation complete."
}

install_wings_docker() {
    install_docker_engine
    configure_firewall_wings
    collect_docker_wings_config
    write_docker_compose_wings
    state_set "wings" "installed"
    state_set "wings_mode" "docker"
    success "Wings Docker setup complete."
}

install_wings() {
    local mode; mode="$(state_get install_mode)"
    if [[ -z "$mode" ]]; then
        echo
        echo -e " ${YELLOW}No panel has been installed via this script yet.${NC}"
        echo -e " Wings install mode cannot be determined automatically."
        echo
        local chosen
        chosen=$(select_option "How do you want to install Wings?" \
            "Native (upstream installer)" \
            "Docker container")
        case "$chosen" in
            1) mode="native" ;;
            2) mode="docker" ;;
        esac
    fi
    if [[ "$mode" == "docker" ]]; then
        install_wings_docker
    else
        install_wings_native
    fi
}

# ============================================================================
# REVIACTYL
# ============================================================================
install_reviactyl() {
    step "Reviactyl Installation"
    echo
    echo -e " ${CYAN}Installing Reviactyl Panel...${NC}"
    echo -e " ${YELLOW}Have your panel URL and API key ready.${NC}\n"

    local rev_url; rev_url="$(ask_input 'Reviactyl panel URL (e.g. https://panel.example.com)')"
    local rev_key; rev_key="$(ask_input 'Reviactyl API key')"

    info "Running Reviactyl installer..."
    bash <(curl -sSL "$REVIACTYL_INSTALLER_URL") <<< "y\n${rev_url}\n${rev_key}"

    state_set "reviactyl" "installed"
    state_set "install_mode" "native"
    success "Reviactyl installer finished."
}

# ============================================================================
# PYRODACTYL
# ============================================================================
install_pyrodactyl() {
    step "Pyrodactyl configuration"
    local dir
    dir="$(ask_input 'Install directory' '/opt/pyrodactyl')"
    install_docker_engine
    ensure_git_repo "$PYRODACTYL_REPO_URL" "$dir"
    state_set "pyrodactyl_dir" "$dir"
    state_set "pyrodactyl" "installed"
    state_set "install_mode" "docker"
    echo
    info "Repository ready at $dir — copy .env.example to .env, fill the values and start the app."
    success "Pyrodactyl prepared."
}

# ============================================================================
# ELYTRA
# ============================================================================
install_elytra() {
    step "Elytra configuration"
    local dir
    dir="$(ask_input 'Install directory' '/opt/elytra')"
    install_docker_engine
    ensure_git_repo "$ELYTRA_REPO_URL" "$dir"
    state_set "elytra_dir" "$dir"
    state_set "elytra" "installed"
    echo
    info "Repository ready at $dir — copy .env.example to .env, fill the values and start the app."
    success "Elytra prepared."
}

# ============================================================================
# BLUEPRINT
# ============================================================================
install_blueprint() {
    step "Blueprint — Extension Framework for Pterodactyl"
    echo
    echo -e " ${CYAN}Blueprint${NC} is an extension framework that only works on a ${BOLD}native${NC} Pterodactyl panel."
    echo -e " It is ${RED}not compatible${NC} with the Dockerized panel, Reviactyl or Pyrodactyl."
    echo

    local mode; mode="$(state_get install_mode)"
    if [[ "$mode" == "docker" ]]; then
        error "Your panel was installed in Docker mode — Blueprint is NOT supported in this configuration."
        echo -e " ${YELLOW}Blueprint requires direct filesystem access to /var/www/pterodactyl and PHP.${NC}"
        echo -e " Install a native panel first if you want to use Blueprint."
        return 1
    fi

    if [[ "$mode" != "native" ]]; then
        warn "No panel install mode detected in state. Blueprint req#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_VERSION="3.0.0"
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
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

BLUEPRINT_INSTALLER_URL="https://get.blueprint.zip"
PYRODACTYL_REPO_URL="https://github.com/pyrohost/pyrodactyl"
ELYTRA_REPO_URL="https://github.com/pyrohost/elytra"
DOCKER_SCRIPT_URL="https://get.docker.com"
COMPOSE_BIN="/usr/local/bin/docker-compose"
STATE_FILE="/etc/universal-panel-installer/state.json"

mkdir -p /etc/universal-panel-installer
[[ -f "$STATE_FILE" ]] || echo '{}' > "$STATE_FILE"

trap 'echo -e "${RED}[ERROR]${NC} Script failed on line $LINENO — check ${LOG_FILE}"' ERR

print_banner() {
    clear || true
    echo -e "${CYAN}${BOLD}"
    cat <<'BANNER'
 ██╗   ██╗███╗   ██╗██╗██╗   ██╗███████╗██████╗ ███████╗ █████╗ ██╗
 ██║   ██║████╗  ██║██║██║   ██║██╔════╝██╔══██╗██╔════╝██╔══██╗██║
 ██║   ██║██╔██╗ ██║██║██║   ██║█████╗  ██████╔╝███████╗███████║██║
 ██║   ██║██║╚██╗██║██║╚██╗ ██╔╝██╔══╝  ██╔══██╗╚════██║██╔══██║██║
 ╚██████╔╝██║ ╚████║██║ ╚████╔╝ ███████╗██║  ██║███████║██║  ██║███████╗
  ╚═════╝ ╚═╝  ╚═══╝╚═╝  ╚═══╝  ╚══════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚══════╝
 ██████╗  █████╗ ███╗   ██╗███████╗██╗         ██╗███╗   ██╗███████╗████████╗
 ██╔══██╗██╔══██╗████╗  ██║██╔════╝██║         ██║████╗  ██║██╔════╝╚══██╔══╝
 ██████╔╝███████║██╔██╗ ██║█████╗  ██║         ██║██╔██╗ ██║███████╗   ██║
 ██╔═══╝ ██╔══██║██║╚██╗██║██╔══╝  ██║         ██║██║╚██╗██║╚════██║   ██║
 ██║     ██║  ██║██║ ╚████║███████╗███████╗     ██║██║ ╚████║███████║   ██║
 ╚═╝     ╚═╝  ╚═╝╚═╝  ╚═══╝╚══════╝╚══════╝     ╚═╝╚═╝  ╚═══╝╚══════╝   ╚═╝
BANNER
    echo -e "${NC}"
    echo -e " ${CYAN}Universal Panel Installer${NC} ${BOLD}v${SCRIPT_VERSION}${NC}"
    echo -e " ${CYAN}Log:${NC} ${LOG_FILE}"
    echo
}

info() { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }
step() { echo -e "\n${MAGENTA}${BOLD}>>> $*${NC}"; }

require_root() {
    if [[ ${EUID} -ne 0 ]]; then
        error "Run this script as root: sudo bash install.sh"
        exit 1
    fi
}

pause() { echo; read -r -p "Press Enter to return to the menu..." _; }

ask_input() {
    local prompt="$1" default_value="${2:-}" value
    if [[ -n "$default_value" ]]; then
        read -r -p " ${CYAN}?${NC} $prompt [${default_value}]: " value
        echo "${value:-$default_value}"
    else
        while true; do
            read -r -p " ${CYAN}?${NC} $prompt: " value
            [[ -n "$value" ]] && break
            warn "This field cannot be empty."
        done
        echo "$value"
    fi
}

ask_input_optional() {
    local prompt="$1" value
    read -r -p " ${CYAN}?${NC} $prompt (press Enter to skip): " value
    echo "$value"
}

ask_password() {
    local prompt="$1" value confirm
    while true; do
        read -r -s -p " ${CYAN}?${NC} $prompt: " value; echo
        [[ -n "$value" ]] && break
        warn "Password cannot be empty."
    done
    read -r -s -p " ${CYAN}?${NC} Confirm password: " confirm; echo
    if [[ "$value" != "$confirm" ]]; then
        warn "Passwords do not match, try again."
        ask_password "$prompt"
        return
    fi
    echo "$value"
}

ask_yes_no() {
    local prompt="$1" default_answer="${2:-y}" answer suffix="[Y/n]"
    [[ "$default_answer" == "n" ]] && suffix="[y/N]"
    while true; do
        read -r -p " ${CYAN}?${NC} $prompt $suffix: " answer
        answer="${answer:-$default_answer}"
        case "$answer" in
            y|Y|yes|YES) return 0 ;;
            n|N|no|NO) return 1 ;;
            *) warn "Please answer yes or no." ;;
        esac
    done
}

select_option() {
    local title="$1"; shift
    local options=("$@")
    echo -e " ${BOLD}$title${NC}"
    local i=1
    for o in "${options[@]}"; do echo " $i) $o"; ((i++)); done
    local choice
    while true; do
        read -r -p " Your choice [1-${#options[@]}]: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options[@]} )); then
            echo "$choice"; return 0
        fi
        warn "Invalid choice."
    done
}

generate_app_key() {
    python3 -c "import secrets,base64; print('base64:' + base64.b64encode(secrets.token_bytes(32)).decode())" 2>/dev/null \
        || openssl rand -base64 32 | awk '{print "base64:" $1}'
}

state_set() {
    local key="$1" val="$2"
    local tmp; tmp="$(mktemp)"
    jq --arg k "$key" --arg v "$val" '.[$k] = $v' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

state_get() {
    jq -r --arg k "$1" '.[$k] // empty' "$STATE_FILE"
}

ensure_supported_os() {
    [[ -f /etc/os-release ]] || { error "/etc/os-release not found"; exit 1; }
    . /etc/os-release
    info "Detected OS: ${PRETTY_NAME:-Unknown Linux}"
    case "${ID:-}" in
        ubuntu|debian) success "Supported distribution." ;;
        *)
            warn "This script is optimized for Ubuntu/Debian."
            ask_yes_no "Continue on unsupported distro?" "n" || exit 1
            ;;
    esac
}

install_base_packages() {
    info "Installing base dependencies..."
    apt-get update -y >/dev/null 2>&1
    apt-get upgrade -y >/dev/null 2>&1
    apt-get install -y curl wget git jq ca-certificates lsb-release gnupg \
        apt-transport-https software-properties-common unzip tar ufw sudo bash-completion python3 >/dev/null 2>&1
    success "Base dependencies installed."
}

configure_firewall_panel() {
    if ask_yes_no "Configure UFW firewall for the panel? (opens 22, 80, 443, 8080)" "y"; then
        ufw allow 22/tcp || true; ufw allow 80/tcp || true
        ufw allow 443/tcp || true; ufw allow 8080/tcp || true
        if ask_yes_no "Enable UFW now?" "n"; then ufw --force enable; fi
        success "Panel firewall rules applied."
    fi
}

configure_firewall_wings() {
    if ask_yes_no "Configure UFW firewall for Wings? (opens 22, 8080, 2022)" "y"; then
        ufw allow 22/tcp || true; ufw allow 8080/tcp || true; ufw allow 2022/tcp || true
        if ask_yes_no "Enable UFW now?" "n"; then ufw --force enable; fi
        success "Wings firewall rules applied."
    fi
}uires a native Pterodactyl panel."
        if ! ask_yes_no "Continue anyway? (only if you have a native panel already installed)" "n"; then
            return 0
        fi
    fi

    local panel_dir
    panel_dir="$(ask_input 'Pterodactyl panel directory' '/var/www/pterodactyl')"

    if [[ ! -d "$panel_dir" ]]; then
        error "Directory $panel_dir does not exist."
        echo -e " ${YELLOW}Make sure Pterodactyl is installed at that path before running Blueprint.${NC}"
        return 1
    fi

    info "Downloading and running the official Blueprint installer from blueprint.zip..."
    cd "$panel_dir"
    bash <(curl -sSL "$BLUEPRINT_INSTALLER_URL")

    state_set "blueprint" "installed"
    state_set "blueprint_dir" "$panel_dir"
    success "Blueprint installation finished."
    echo
    info "You can now install Blueprint extensions (.blueprint files) from the panel admin area."
}

install_docker_engine() {
    if command -v docker >/dev/null 2>&1; then
        success "Docker already installed: $(docker --version)"
    else
        info "Installing Docker via official script..."
        curl -fsSL "$DOCKER_SCRIPT_URL" | sh >/dev/null 2>&1
        systemctl enable --now docker
        success "Docker installed and started."
    fi
    if docker compose version >/dev/null 2>&1; then
        success "Docker Compose plugin available."
    else
        apt-get install -y docker-compose-plugin >/dev/null 2>&1 || true
        if ! docker compose version >/dev/null 2>&1; then
            curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
                -o "$COMPOSE_BIN" && chmod +x "$COMPOSE_BIN"
            success "Standalone docker-compose installed."
        fi
    fi
}

ensure_git_repo() {
    local url="$1" dir="$2"
    if [[ -d "$dir/.git" ]]; then
        info "Updating repo in $dir"
        git -C "$dir" pull --ff-only
    else
        info "Cloning $url into $dir"
        git clone "$url" "$dir"
    fi
}

collect_docker_panel_config() {
    step "Docker panel configuration"
    echo -e " ${YELLOW}Fill in every field — all values will be written directly into docker-compose.yml${NC}\n"
    PTERO_STACK_DIR="$(ask_input 'Stack directory on disk' '/opt/pterodactyl')"
    PTERO_DOMAIN="$(ask_input 'Panel domain (e.g. panel.example.com)')"
    PTERO_TIMEZONE="$(ask_input 'Server timezone' 'Europe/Rome')"
    step "Database credentials"
    PTERO_DB_NAME="$(ask_input 'Database name' 'panel')"
    PTERO_DB_USER="$(ask_input 'Database user' 'pterodactyl')"
    PTERO_DB_PASS="$(ask_password 'Database user password')"
    PTERO_DB_ROOT_PASS="$(ask_password 'MariaDB root password')"
    step "Application key"
    local generated_key; generated_key="$(generate_app_key)"
    info "Auto-generated APP_KEY: ${generated_key}"
    local custom_key
    custom_key="$(ask_input_optional 'Enter a custom APP_KEY or leave blank to use the generated one')"
    PTERO_APP_KEY="${custom_key:-$generated_key}"
    step "Mail configuration (optional — press Enter on each field to skip)"
    PTERO_MAIL_HOST="$(ask_input_optional 'SMTP host (e.g. smtp.gmail.com)')"
    PTERO_MAIL_PORT="$(ask_input_optional 'SMTP port (e.g. 587)')"
    PTERO_MAIL_USER="$(ask_input_optional 'SMTP username / email')"
    PTERO_MAIL_PASS=""
    if [[ -n "$PTERO_MAIL_HOST" ]]; then
        read -r -s -p " ${CYAN}?${NC} SMTP password (Enter to skip): " PTERO_MAIL_PASS; echo
    fi
    PTERO_MAIL_FROM="$(ask_input_optional 'From address (e.g. noreply@example.com)')"
    PTERO_MAIL_FROM_NAME="$(ask_input_optional 'From name (e.g. Pterodactyl)')"
    PTERO_MAIL_ENCRYPTION="$(ask_input_optional 'Encryption: tls or ssl (default: tls)')"
    PTERO_MAIL_ENCRYPTION="${PTERO_MAIL_ENCRYPTION:-tls}"
}

write_docker_compose_pterodactyl() {
    local d="$PTERO_STACK_DIR"
    mkdir -p "$d/nginx/conf.d" "$d/panel/var" "$d/mariadb" "$d/redis"
    local mail_env=""
    if [[ -n "$PTERO_MAIL_HOST" ]]; then
        mail_env=" MAIL_DRIVER: smtp
 MAIL_HOST: ${PTERO_MAIL_HOST}
 MAIL_PORT: ${PTERO_MAIL_PORT:-587}
 MAIL_USERNAME: ${PTERO_MAIL_USER}
 MAIL_PASSWORD: ${PTERO_MAIL_PASS}
 MAIL_ENCRYPTION: ${PTERO_MAIL_ENCRYPTION}
 MAIL_FROM: ${PTERO_MAIL_FROM}
 MAIL_FROM_NAME: ${PTERO_MAIL_FROM_NAME}"
    fi
    cat > "$d/docker-compose.yml" <<COMPOSE
services:
 mariadb:
  image: mariadb:11
  container_name: ptero-mariadb
  restart: unless-stopped
  environment:
   MYSQL_ROOT_PASSWORD: ${PTERO_DB_ROOT_PASS}
   MYSQL_DATABASE: ${PTERO_DB_NAME}
   MYSQL_USER: ${PTERO_DB_USER}
   MYSQL_PASSWORD: ${PTERO_DB_PASS}
   TZ: ${PTERO_TIMEZONE}
  volumes:
   - ./mariadb:/var/lib/mysql
 redis:
  image: redis:7-alpine
  container_name: ptero-redis
  restart: unless-stopped
  command: redis-server --appendonly yes
 ptero-panel:
  image: ghcr.io/pterodactyl/panel:latest
  container_name: ptero-panel
  restart: unless-stopped
  environment:
   APP_URL: "https://${PTERO_DOMAIN}"
   APP_TIMEZONE: ${PTERO_TIMEZONE}
   APP_KEY: "${PTERO_APP_KEY}"
   APP_ENV: production
   APP_DEBUG: "false"
   DB_HOST: mariadb
   DB_PORT: 3306
   DB_DATABASE: ${PTERO_DB_NAME}
   DB_USERNAME: ${PTERO_DB_USER}
   DB_PASSWORD: ${PTERO_DB_PASS}
   REDIS_HOST: redis
   CACHE_DRIVER: redis
   SESSION_DRIVER: redis
   QUEUE_CONNECTION: redis${mail_env}
  volumes:
   - ./panel/var:/app/var
 nginx:
  image: nginx:alpine
  container_name: ptero-nginx
  restart: unless-stopped
  depends_on:
   - ptero-panel
  ports:
   - "80:80"
   - "443:443"
  volumes:
   - ./nginx/conf.d:/etc/nginx/conf.d
COMPOSE
    cat > "$d/nginx/conf.d/panel.conf" <<NGINX
server {
 listen 80;
 server_name ${PTERO_DOMAIN};
 location / {
  proxy_pass http://ptero-panel:80;
  proxy_set_header Host \$host;
  proxy_set_header X-Real-IP \$remote_addr;
  proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
  proxy_set_header X-Forwarded-Proto \$scheme;
 }
}
NGINX
    state_set "docker_panel_dir" "$d"
    state_set "docker_panel_domain" "$PTERO_DOMAIN"
    success "All panel files written to $d"
    echo
    info "Start the stack with:"
    echo " cd $d && docker compose up -d"
}

collect_docker_wings_config() {
    step "Docker Wings configuration"
    echo -e " ${YELLOW}Wings will run as a Docker container alongside the panel stack.${NC}\n"
    WINGS_STACK_DIR="$(ask_input 'Wings stack directory' "${PTERO_STACK_DIR:-/opt/pterodactyl}")"
    WINGS_TOKEN_ID="$(ask_input 'Wings token ID (from panel node page)')"
    WINGS_TOKEN="$(ask_input 'Wings token (from panel node page)')"
    WINGS_PANEL_URL="$(ask_input 'Panel URL (e.g. https://panel.example.com)')"
    WINGS_NODE_UUID="$(ask_input 'Node UUID (from panel node page)')"
    WINGS_TIMEZONE="$(ask_input 'Server timezone' "${PTERO_TIMEZONE:-Europe/Rome}")"
}

write_docker_compose_wings() {
    local d="$WINGS_STACK_DIR"
    mkdir -p "$d/wings/etc" "$d/wings/tmp"
    cat > "$d/wings-compose.yml" <<COMPOSE
services:
 wings:
  image: ghcr.io/pterodactyl/wings:latest
  container_name: ptero-wings
  restart: unless-stopped
  network_mode: host
  privileged: true
  environment:
   TZ: ${WINGS_TIMEZONE}
  volumes:
   - /var/run/docker.sock:/var/run/docker.sock
   - /var/lib/docker/containers:/var/lib/docker/containers
   - ./wings/etc:/etc/pterodactyl
   - ./wings/tmp:/tmp/pterodactyl
   - /tmp/pterodactyl:/tmp/pterodactyl
COMPOSE
    mkdir -p "$d/wings/etc"
    cat > "$d/wings/etc/config.yml" <<WINGSCFG
debug: false
uuid: ${WINGS_NODE_UUID}
token_id: ${WINGS_TOKEN_ID}
token: ${WINGS_TOKEN}
api:
 host: 0.0.0.0
 port: 8080
 ssl:
  enabled: false
 upload_limit: 100
system:
 data: /var/lib/pterodactyl/volumes
 sftp:
  bind_port: 2022
remote: ${WINGS_PANEL_URL}
allowed_mounts: []
WINGSCFG
    state_set "wings_docker_dir" "$d"
    success "Wings Docker files written to $d"
    echo
    info "Start Wings with:"
    echo " cd $d && docker compose -f wings-compose.yml up -d"
}

install_pterodactyl_native() {
    step "Pterodactyl Panel — Native Installation"
    echo
    echo -e " ${YELLOW}This will install Pterodactyl Panel natively on this machine.${NC}"
    echo -e " ${YELLOW}The script will ask you for web server, DB, SSL and SMTP settings.${NC}\n"
    
    configure_firewall_panel
    
    info "Installing Pterodactyl dependencies..."
    apt-get update -y >/dev/null 2>&1
    LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php >/dev/null 2>&1 || true
    curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg 2>/dev/null || true
    echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/redis.list >/dev/null 2>&1 || true
    apt-get update -y >/dev/null 2>&1
    apt-get install -y php8.3 php8.3-common php8.3-cli php8.3-gd php8.3-mysql php8.3-mbstring php8.3-bcmath php8.3-xml php8.3-fpm php8.3-curl php8.3-zip mariadb-server nginx tar unzip git redis-server >/dev/null 2>&1
    success "Dependencies installed."
    
    info "Installing Composer..."
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer >/dev/null 2>&1
    success "Composer installed."
    
    local panel_dir="/var/www/pterodactyl"
    mkdir -p "$panel_dir"
    cd "$panel_dir"
    
    info "Downloading Pterodactyl panel..."
    curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz >/dev/null 2>&1
    tar -xzvf panel.tar.gz >/dev/null 2>&1
    chmod -R 755 storage/* bootstrap/cache/
    success "Panel files downloaded."
    
    step "Database setup"
    local db_pass; db_pass="$(ask_password 'Database password for pterodactyl user')"
    local db_root_pass; db_root_pass="$(ask_password 'MariaDB root password')"
    
    mariadb -u root -e "CREATE DATABASE IF NOT EXISTS panel; CREATE USER IF NOT EXISTS 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '${db_pass}'; GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION; FLUSH PRIVILEGES;"
    success "Database created."
    
    cp .env.example .env
    COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader >/dev/null 2>&1
    php artisan key:generate --force
    
    info "Running environment setup wizard..."
    php artisan p:environment:setup
    php artisan p:environment:database
    php artisan p:environment:mail
    
    info "Running database migrations..."
    php artisan migrate --seed --force >/dev/null 2>&1
    success "Database migrated."
    
    step "Create admin user"
    local admin_email admin_user admin_pass admin_first admin_last
    admin_email="$(ask_input 'Admin email')"
    admin_user="$(ask_input 'Admin username')"
    admin_pass="$(ask_password 'Admin password')"
    admin_first="$(ask_input 'Admin first name' 'Admin')"
    admin_last="$(ask_input 'Admin last name' 'User')"
    
    php artisan p:user:make --email="$admin_email" --username="$admin_user" --name-first="$admin_first" --name-last="$admin_last" --password="$admin_pass" --admin=1
    success "Admin user created."
    
    chown -R www-data:www-data "$panel_dir"/*
    (crontab -l 2>/dev/null | grep -v 'artisan schedule:run'; echo "* * * * * php ${panel_dir}/artisan schedule:run >> /dev/null 2>&1") | crontab -
    success "Cron configured."
    
    cat > /etc/systemd/system/pteroq.service <<SYSTEMD
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service

[Service]
User=www-data
Group=www-data
Restart=on-failure
StartLimitInterval=600
StartLimitBurst=10
WorkingDirectory=${panel_dir}
ExecStart=/usr/bin/php ${panel_dir}/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
SYSTEMD
    systemctl daemon-reload
    systemctl enable --now redis-server pteroq >/dev/null 2>&1
    success "Queue worker configured."
    
    state_set "pterodactyl_native" "installed"
    state_set "install_mode" "native"
    state_set "pterodactyl_dir" "$panel_dir"
    success "Native Pterodactyl panel installation complete."
}

install_pterodactyl_docker() {
    collect_docker_panel_config
    install_docker_engine
    configure_firewall_panel
    write_docker_compose_pterodactyl
    state_set "pterodactyl_docker" "installed"
    state_set "install_mode" "docker"
}

choose_panel_mode() {
    local mode
    mode=$(select_option "How do you want to install the Pterodactyl panel?" \
        "Native on the machine" \
        "Dockerized stack (fully configured by this script)")
    case "$mode" in
        1) install_pterodactyl_native ;;
        2) install_pterodactyl_docker ;;
    esac
}

# ============================================================================
# WINGS — NATIVE (via upstream installer)
# ============================================================================
install_wings_native() {
    step "Wings — Native Installation"
    echo
    echo -e " ${YELLOW}Installing Wings via the official upstream installer.${NC}"
    echo -e " ${YELLOW}You will be guided through node configuration.${NC}\n"

    configure_firewall_wings
    install_docker_engine

    # Run the upstream wings installer (option 2 = wings only)
    bash <(curl -s https://raw.githubusercontent.com/pterodactyl-installer/pterodactyl-installer/master/install.sh) <<< "2"

    state_set "wings" "installed"
    state_set "wings_mode" "native"
    success "Wings native installation complete."
}

install_wings_docker() {
    install_docker_engine
    configure_firewall_wings
    collect_docker_wings_config
    write_docker_compose_wings
    state_set "wings" "installed"
    state_set "wings_mode" "docker"
    success "Wings Docker setup complete."
}

install_wings() {
    local mode; mode="$(state_get install_mode)"
    if [[ -z "$mode" ]]; then
        echo
        echo -e " ${YELLOW}No panel has been installed via this script yet.${NC}"
        echo -e " Wings install mode cannot be determined automatically."
        echo
        local chosen
        chosen=$(select_option "How do you want to install Wings?" \
            "Native (upstream installer)" \
            "Docker container")
        case "$chosen" in
            1) mode="native" ;;
            2) mode="docker" ;;
        esac
    fi
    if [[ "$mode" == "docker" ]]; then
        install_wings_docker
    else
        install_wings_native
    fi
}

# ============================================================================
# REVIACTYL
# ============================================================================
install_reviactyl() {
    step "Reviactyl Installation"
    echo
    echo -e " ${CYAN}Installing Reviactyl Panel...${NC}"
    echo -e " ${YELLOW}Have your panel URL and API key ready.${NC}\n"

    local rev_url; rev_url="$(ask_input 'Reviactyl panel URL (e.g. https://panel.example.com)')"
    local rev_key; rev_key="$(ask_input 'Reviactyl API key')"

    info "Running Reviactyl installer..."
    bash <(curl -sSL "$REVIACTYL_INSTALLER_URL") <<< "y\n${rev_url}\n${rev_key}"

    state_set "reviactyl" "installed"
    state_set "install_mode" "native"
    success "Reviactyl installer finished."
}

# ============================================================================
# PYRODACTYL
# ============================================================================
install_pyrodactyl() {
    step "Pyrodactyl configuration"
    local dir
    dir="$(ask_input 'Install directory' '/opt/pyrodactyl')"
    install_docker_engine
    ensure_git_repo "$PYRODACTYL_REPO_URL" "$dir"
    state_set "pyrodactyl_dir" "$dir"
    state_set "pyrodactyl" "installed"
    state_set "install_mode" "docker"
    echo
    info "Repository ready at $dir — copy .env.example to .env, fill the values and start the app."
    success "Pyrodactyl prepared."
}

# ============================================================================
# ELYTRA
# ============================================================================
install_elytra() {
    step "Elytra configuration"
    local dir
    dir="$(ask_input 'Install directory' '/opt/elytra')"
    install_docker_engine
    ensure_git_repo "$ELYTRA_REPO_URL" "$dir"
    state_set "elytra_dir" "$dir"
    state_set "elytra" "installed"
    echo
    info "Repository ready at $dir — copy .env.example to .env, fill the values and start the app."
    success "Elytra prepared."
}

# ============================================================================
# BLUEPRINT
# ============================================================================
install_blueprint() {
    step "Blueprint — Extension Framework for Pterodactyl"
    echo
    echo -e " ${CYAN}Blueprint${NC} is an extension framework that only works on a ${BOLD}native${NC} Pterodactyl panel."
    echo -e " It is ${RED}not compatible${NC} with the Dockerized panel, Reviactyl or Pyrodactyl."
    echo

    local mode; mode="$(state_get install_mode)"
    if [[ "$mode" == "docker" ]]; then
        error "Your panel was installed in Docker mode — Blueprint is NOT supported in this configuration."
        echo -e " ${YELLOW}Blueprint requires direct filesystem access to /var/www/pterodactyl and PHP.${NC}"
        echo -e " Install a native panel first if you want to use Blueprint."
        return 1
    fi

    if [[ "$mode" != "native" ]]; then
        warn "No panel install mode detected in state. Blueprint requires a native Pterodactyl panel."
        if ! ask_yes_no "Continue anyway? (only if you have a native panel already installed)" "n"; then
            return 0
        fi
    fi

    local panel_dir
    panel_dir="$(ask_input 'Pterodactyl panel directory' '/var/www/pterodactyl')"

    if [[ ! -d "$panel_dir" ]]; then
        error "Directory $panel_dir does not exist."
        echo -e " ${YELLOW}Make sure Pterodactyl is installed at that path before running Blueprint.${NC}"
        return 1
    fi

    info "Downloading and running the official Blueprint installer from blueprint.zip..."
    cd "$panel_dir"
    bash <(curl -sSL "$BLUEPRINT_INSTALLER_URL")

    state_set "blueprint" "installed"
    state_set "blueprint_dir" "$panel_dir"
    success "Blueprint installation finished."
    echo
    info "You can now install Blueprint extensions (.blueprint files) from the panel admin area."
}

# ============================================================================
# DIAGNOSTICS
# ============================================================================
check_ok() { echo -e " ${GREEN}[OK]${NC} $*"; }
check_fail() { echo -e " ${RED}[FAIL]${NC} $*"; DIAG_PROBLEMS+=( "$*" ); }
check_warn() { echo -e " ${YELLOW}[WARN]${NC} $*"; DIAG_WARNINGS+=( "$*" ); }

diag_docker() {
    echo -e " ${BOLD}Docker${NC}"
    if command -v docker >/dev/null 2>&1; then
        check_ok "Docker installed: $(docker --version 2>/dev/null)"
        if systemctl is-active --quiet docker 2>/dev/null; then
            check_ok "Docker daemon is running"
        else
            check_fail "Docker daemon is NOT running — fix: systemctl start docker"
        fi
        if docker compose version >/dev/null 2>&1; then
            check_ok "Docker Compose available: $(docker compose version 2>/dev/null)"
        else
            check_warn "Docker Compose not found — install with: apt-get install docker-compose-plugin"
        fi
    else
        check_warn "Docker is not installed"
    fi
}

diag_pterodactyl_native() {
    echo -e " ${BOLD}Pterodactyl panel (native)${NC}"
    if [[ "$(state_get pterodactyl_native)" == "installed" ]]; then
        check_ok "Installed via this script"
    else
        check_warn "Not installed via this script (may still be present manually)"
    fi
    if [[ -f /etc/pterodactyl/config.yml ]] || [[ -d /var/www/pterodactyl ]]; then
        check_ok "Panel directory or config found on disk"
    else
        check_warn "Panel directory/config not detected at standard paths"
    fi
    for svc in nginx apache2; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            check_ok "Web server ($svc) is running"
        fi
    done
    for svc in mariadb mysql; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            check_ok "Database ($svc) is running"
        fi
    done
    if systemctl is-active --quiet pteroq 2>/dev/null; then
        check_ok "Queue worker (pteroq) is running"
    else
        check_fail "Queue worker (pteroq) is not running — fix: systemctl start pteroq"
    fi
    if crontab -l 2>/dev/null | grep -q 'artisan'; then
        check_ok "Artisan cron entry found"
    else
        check_warn "Artisan cron not detected — add: * * * * * php /var/www/pterodactyl/artisan schedule:run"
    fi
}

diag_pterodactyl_docker() {
    echo -e " ${BOLD}Pterodactyl panel (Docker)${NC}"
    local d; d="$(state_get docker_panel_dir)"
    if [[ -z "$d" ]]; then
        check_warn "No Docker panel path tracked — skipping Docker panel checks"
        return
    fi
    check_ok "Stack directory: $d"
    if [[ -f "$d/docker-compose.yml" ]]; then
        check_ok "docker-compose.yml exists"
    else
        check_fail "docker-compose.yml missing in $d"
    fi
    for cname in ptero-mariadb ptero-redis ptero-panel ptero-nginx; do
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$cname"; then
            check_ok "Container running: $cname"
        else
            check_fail "Container NOT running: $cname — fix: cd $d && docker compose up -d"
        fi
    done
}

diag_wings_native() {
    echo -e " ${BOLD}Wings (native)${NC}"
    if command -v wings >/dev/null 2>&1; then
        check_ok "Wings binary found: $(wings --version 2>/dev/null || echo 'version unknown')"
    else
        check_warn "Wings binary not found at standard path"
    fi
    if [[ -f /etc/pterodactyl/config.yml ]]; then
        check_ok "/etc/pterodactyl/config.yml present"
        if grep -q 'uuid' /etc/pterodactyl/config.yml 2>/dev/null; then
            check_ok "config.yml contains node UUID"
        else
            check_fail "config.yml seems incomplete — regenerate from panel node page"
        fi
    else
        check_fail "/etc/pterodactyl/config.yml not found — paste it from the panel node page"
    fi
    if systemctl is-active --quiet wings 2>/dev/null; then
        check_ok "Wings service is running"
    else
        check_fail "Wings service is NOT running — fix: systemctl enable --now wings"
    fi
}

diag_wings_docker() {
    echo -e " ${BOLD}Wings (Docker)${NC}"
    local d; d="$(state_get wings_docker_dir)"
    if [[ -z "$d" ]]; then
        check_warn "No Wings Docker path tracked — skipping"
        return
    fi
    check_ok "Wings stack directory: $d"
    if [[ -f "$d/wings-compose.yml" ]]; then
        check_ok "wings-compose.yml exists"
    else
        check_fail "wings-compose.yml missing in $d"
    fi
    if [[ -f "$d/wings/etc/config.yml" ]]; then
        check_ok "Wings config.yml present"
        if grep -q 'uuid' "$d/wings/etc/config.yml" 2>/dev/null; then
            check_ok "config.yml contains node UUID"
        else
            check_fail "config.yml seems incomplete — check token_id, token and uuid fields"
        fi
    else
        check_fail "Wings config.yml not found in $d/wings/etc/"
    fi
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "ptero-wings"; then
        check_ok "Container ptero-wings is running"
    else
        check_fail "Container ptero-wings is NOT running — fix: cd $d && docker compose -f wings-compose.yml up -d"
    fi
}

diag_blueprint() {
    echo -e " ${BOLD}Blueprint${NC}"
    local dir; dir="$(state_get blueprint_dir)"
    if [[ -z "$dir" ]]; then
        check_warn "No Blueprint path tracked — skipping"
        return
    fi
    check_ok "Blueprint installed in: $dir"
    if [[ -f "$dir/blueprint.sh" ]]; then
        check_ok "blueprint.sh found"
        local ver
        ver="$(bash "$dir/blueprint.sh" --version 2>/dev/null || echo 'unknown')"
        check_ok "Blueprint version: $ver"
    else
        check_warn "blueprint.sh not found at $dir — Blueprint may not be fully installed"
    fi
    if [[ -d "$dir/extensions" ]]; then
        local ext_count
        ext_count="$(find "$dir/extensions" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)"
        check_ok "Extensions installed: $ext_count"
    fi
}

diag_reviactyl() {
    echo -e " ${BOLD}Reviactyl${NC}"
    if [[ "$(state_get reviactyl)" == "installed" ]]; then
        check_ok "Installed via this script"
    else
        check_warn "Not installed via this script (may still be present manually)"
    fi
    for cname in reviactyl; do
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -qi "$cname"; then
            check_ok "Reviactyl container running"
        fi
    done
}

diag_pyrodactyl() {
    echo -e " ${BOLD}Pyrodactyl${NC}"
    local dir; dir="$(state_get pyrodactyl_dir)"
    if [[ -z "$dir" ]]; then
        check_warn "No Pyrodactyl path tracked — skipping"
        return
    fi
    if [[ -d "$dir/.git" ]]; then
        check_ok "Repository present at $dir"
        local last_commit; last_commit="$(git -C "$dir" log -1 --format='%h %s' 2>/dev/null)"
        check_ok "Last commit: $last_commit"
    else
        check_fail "Repository not found at $dir"
    fi
    if [[ -f "$dir/.env" ]]; then
        check_ok ".env file found"
        if grep -qE '^APP_KEY=.+' "$dir/.env" 2>/dev/null; then
            check_ok "APP_KEY is set in .env"
        else
            check_fail "APP_KEY is missing or empty in .env"
        fi
        if grep -qE '^DB_(HOST|DATABASE)=' "$dir/.env" 2>/dev/null; then
            check_ok "Database vars found in .env"
        else
            check_warn "DB_HOST / DB_DATABASE not found in .env"
        fi
    else
        check_fail ".env file not found — copy .env.example to .env and fill the values"
    fi
}

diag_elytra() {
    echo -e " ${BOLD}Elytra${NC}"
    local dir; dir="$(state_get elytra_dir)"
    if [[ -z "$dir" ]]; then
        check_warn "No Elytra path tracked — skipping"
        return
    fi
    if [[ -d "$dir/.git" ]]; then
        check_ok "Repository present at $dir"
        local last_commit; last_commit="$(git -C "$dir" log -1 --format='%h %s' 2>/dev/null)"
        check_ok "Last commit: $last_commit"
    else
        check_fail "Repository not found at $dir"
    fi
    if [[ -f "$dir/.env" ]]; then
        check_ok ".env file found"
    else
        check_fail ".env file not found — copy .env.example to .env and fill the values"
    fi
}

diag_system() {
    echo -e " ${BOLD}System${NC}"
    local ram_mb; ram_mb=$(free -m | awk '/Mem:/{print $2}')
    if (( ram_mb >= 1024 )); then
        check_ok "RAM: ${ram_mb}MB"
    else
        check_warn "RAM is low (${ram_mb}MB) — at least 1GB recommended"
    fi
    local disk_free; disk_free=$(df -BG / | awk 'NR==2{gsub(/G/,"",$4); print $4}')
    if (( disk_free >= 10 )); then
        check_ok "Free disk: ${disk_free}GB"
    else
        check_warn "Low disk space (${disk_free}GB free) — at least 10GB recommended"
    fi
    if systemctl is-active --quiet ufw 2>/dev/null; then
        check_ok "UFW firewall is active"
    else
        check_warn "UFW is not active — consider enabling it"
    fi
}

fix_menu() {
    local problems=("$@")
    echo
    echo -e " ${RED}${BOLD}The following problems were found:${NC}"
    local i=1
    for p in "${problems[@]}"; do
        echo -e " ${i}) ${RED}${p}${NC}"
        ((i++))
    done
    echo
    if ask_yes_no "Do you want the script to attempt auto-fixes for all the problems above?" "y"; then
        for p in "${problems[@]}"; do
            if echo "$p" | grep -q 'Docker daemon is NOT running'; then
                info "Starting Docker daemon..."
                systemctl start docker && check_ok "Docker daemon started" || check_fail "Could not start Docker"
            elif echo "$p" | grep -q 'Container NOT running: ptero-wings'; then
                local wdir; wdir="$(state_get wings_docker_dir)"
                if [[ -n "$wdir" ]]; then
                    info "Starting Wings container in $wdir..."
                    docker compose -f "$wdir/wings-compose.yml" up -d && check_ok "Wings container started" || check_fail "docker compose up failed for Wings"
                fi
            elif echo "$p" | grep -q 'Container NOT running'; then
                local cdir; cdir="$(state_get docker_panel_dir)"
                if [[ -n "$cdir" ]]; then
                    info "Starting Docker Compose stack in $cdir..."
                    docker compose -f "$cdir/docker-compose.yml" up -d && check_ok "Stack started" || check_fail "docker compose up failed"
                fi
            elif echo "$p" | grep -q 'Wings service is NOT running'; then
                info "Enabling and starting Wings..."
                systemctl enable --now wings && check_ok "Wings started" || check_fail "Could not start Wings"
            elif echo "$p" | grep -q 'Queue worker.*not running'; then
                info "Starting pterodactyl queue worker..."
                systemctl start pteroq && check_ok "Queue worker started" || check_fail "Could not start pteroq"
            else
                warn "No automatic fix available for: $p"
                info "You will need to resolve this manually."
            fi
        done
    fi
}

run_diagnostics() {
    print_banner
    step "System health check"
    DIAG_PROBLEMS=()
    DIAG_WARNINGS=()
    diag_system
    echo
    diag_docker
    echo
    
    local has_native; has_native="$(state_get pterodactyl_native)"
    local has_docker; has_docker="$(state_get pterodactyl_docker)"
    local has_wings; has_wings="$(state_get wings)"
    local wings_mode; wings_mode="$(state_get wings_mode)"
    local has_reviactyl; has_reviactyl="$(state_get reviactyl)"
    local has_pyrodactyl; has_pyrodactyl="$(state_get pyrodactyl)"
    local has_elytra; has_elytra="$(state_get elytra)"
    local has_blueprint; has_blueprint="$(state_get blueprint)"
    
    echo -e " ${BOLD}Installed components (tracked by this script):${NC}"
    [[ "$has_native" == "installed" ]] && echo -e " ${GREEN}+${NC} Pterodactyl panel (native)"
    [[ "$has_docker" == "installed" ]] && echo -e " ${GREEN}+${NC} Pterodactyl panel (Docker)"
    [[ "$has_wings" == "installed" ]] && {
        if [[ "$wings_mode" == "docker" ]]; then
            echo -e " ${GREEN}+${NC} Wings (Docker)"
        else
            echo -e " ${GREEN}+${NC} Wings (native)"
        fi
    }
    [[ "$has_reviactyl" == "installed" ]] && echo -e " ${GREEN}+${NC} Reviactyl"
    [[ "$has_pyrodactyl" == "installed" ]] && echo -e " ${GREEN}+${NC} Pyrodactyl"
    [[ "$has_elytra" == "installed" ]] && echo -e " ${GREEN}+${NC} Elytra"
    [[ "$has_blueprint" == "installed" ]] && echo -e " ${GREEN}+${NC} Blueprint"
    echo
    
    [[ "$has_native" == "installed" ]] && { diag_pterodactyl_native; echo; }
    [[ "$has_docker" == "installed" ]] && { diag_pterodactyl_docker; echo; }
    if [[ "$has_wings" == "installed" ]]; then
        if [[ "$wings_mode" == "docker" ]]; then
            diag_wings_docker
        else
            diag_wings_native
        fi
        echo
    fi
    [[ "$has_blueprint" == "installed" ]] && { diag_blueprint; echo; }
    [[ "$has_reviactyl" == "installed" ]] && { diag_reviactyl; echo; }
    [[ "$has_pyrodactyl" == "installed" ]] && { diag_pyrodactyl; echo; }
    [[ "$has_elytra" == "installed" ]] && { diag_elytra; echo; }
    
    echo -e " ${BOLD}Summary${NC}"
    if (( ${#DIAG_PROBLEMS[@]} == 0 )) && (( ${#DIAG_WARNINGS[@]} == 0 )); then
        echo -e " ${GREEN}${BOLD}Everything looks healthy!${NC}"
    else
        if (( ${#DIAG_PROBLEMS[@]} > 0 )); then
            echo -e " ${RED}Problems found: ${#DIAG_PROBLEMS[@]}${NC}"
        fi
        if (( ${#DIAG_WARNINGS[@]} > 0 )); then
            echo -e " ${YELLOW}Warnings found: ${#DIAG_WARNINGS[@]}${NC}"
        fi
        echo
        echo -e " ${BOLD}Warnings (no immediate action needed):${NC}"
        for w in "${DIAG_WARNINGS[@]}"; do echo -e " ${YELLOW}-${NC} $w"; done
        if (( ${#DIAG_PROBLEMS[@]} > 0 )); then
            fix_menu "${DIAG_PROBLEMS[@]}"
        fi
    fi
    echo
    info "Full log saved at $LOG_FILE"
}

main_menu() {
    while true; do
        print_banner
        echo -e " ${BOLD}What do you want to install?${NC}"
        echo
        echo " 1) Pterodactyl panel"
        echo " 2) Wings"
        echo " 3) Pterodactyl panel + Wings"
        echo " 4) Reviactyl"
        echo " 5) Reviactyl + Wings"
        echo " 6) Pyrodactyl"
        echo " 7) Pyrodactyl + Wings"
        echo " 8) Pyrodactyl + Elytra"
        echo " 9) Blueprint (Pterodactyl Panel Only)"
        echo " 10) System diagnostics & health check"
        echo " 0) Exit"
        echo
        
        read -r -p " Your choice: " choice
        echo
        case "$choice" in
            1) choose_panel_mode; pause ;;
            2) install_wings; pause ;;
            3)
                info "Installing Pterodactyl panel first..."
                choose_panel_mode
                info "Installing Wings next..."
                install_wings
                success "Pterodactyl panel + Wings installation complete!"
                pause
                ;;
            4) install_reviactyl; pause ;;
            5) install_reviactyl; install_wings; pause ;;
            6) install_pyrodactyl; pause ;;
            7) install_pyrodactyl; install_wings; pause ;;
            8) install_pyrodactyl; install_elytra; pause ;;
            9) install_blueprint; pause ;;
            10) run_diagnostics; pause ;;
            0) echo -e " ${GREEN}Goodbye!${NC}"; exit 0 ;;
            *) warn "Invalid choice. Please try again."; sleep 1 ;;
        esac
    done
}

main_menu
