#!/bin/bash

set -e  # Exit on error

# ===================== COLOR CODES =====================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ===================== DETECT DEFAULT USER =====================
# Try to detect common VPS users
if [[ -n "$SUDO_USER" ]] && [[ "$SUDO_USER" != "root" ]]; then
    DEFAULT_USER="$SUDO_USER"
elif id "ubuntu" &>/dev/null; then
    DEFAULT_USER="ubuntu"
elif id "admin" &>/dev/null; then
    DEFAULT_USER="admin"
elif id "debian" &>/dev/null; then
    DEFAULT_USER="debian"
else
    DEFAULT_USER="www-data"
fi

# ===================== PROMPT FOR USER =====================
echo -e "${BLUE}Detected default user: ${GREEN}$DEFAULT_USER${NC}"
echo -e "${YELLOW}This user will be used to run the Pterodactyl Panel services.${NC}"
echo

while true; do
    read -p "Enter the username to use for the installation [$DEFAULT_USER]: " INSTALL_USER
    
    # Use default if empty
    if [[ -z "$INSTALL_USER" ]]; then
        INSTALL_USER="$DEFAULT_USER"
    fi
    
    if ! id "$INSTALL_USER" &>/dev/null; then
        echo -e "${RED}❌ User '$INSTALL_USER' does not exist on this system.${NC}"
        read -p "Do you want to create it? (y/n): " yn
        case $yn in
            [Yy]* )
                sudo adduser --disabled-password --gecos "" "$INSTALL_USER"
                if [[ $? -eq 0 ]]; then
                    echo -e "${GREEN}✅ User created successfully.${NC}"
                    break
                else
                    echo -e "${RED}❌ Failed to create user.${NC}"
                fi
                ;;
            [Nn]* )
                echo "Please enter a valid existing username."
                ;;
            * )
                echo "Please answer yes or no."
                ;;
        esac
    else
        echo -e "${GREEN}✅ User '$INSTALL_USER' will be used.${NC}"
        break
    fi
done

# ===================== BANNER =====================
banner(){
cat << "EOF"
 █████  ██████  ███████ ██████   █████   ██████ ████████ ██    ██ ██      ███████ 
██   ██ ██   ██ ██      ██   ██ ██   ██ ██         ██     ██  ██  ██      ██      
███████ ██████  ███████ ██   ██ ███████ ██         ██      ████   ██      █████   
██   ██ ██   ██      ██ ██   ██ ██   ██ ██         ██       ██    ██      ██      
██   ██ ██   ██ ███████ ██████  ██   ██  ██████    ██       ██    ███████ ███████ 
                                                                                  
EOF
}

# ===================== PANEL INSTALL =====================
panel_install(){
    echo -e "${GREEN}Starting Panel Installation...${NC}"
    
    # Default DB values
    panel_db_host="127.0.0.1"
    panel_db_name="panel"
    panel_db_user="pterodactyl"
    panel_db_password=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)

    user_email=""
    user_username="admin"
    user_firstname=""
    user_lastname=""
    user_password=""
    panel_url=""
    panel_timezone="UTC"

    # ===================== PROMPT FUNCTIONS =====================
    prompt() {
        local var_name="$1"
        local prompt_text="$2"
        local default_value="$3"
        read -p "$prompt_text [$default_value]: " input
        if [[ -n "$input" ]]; then
            eval "$var_name=\"\$input\""
        else
            eval "$var_name=\"\$default_value\""
        fi
    }

    prompt_required() {
        local var_name="$1"
        local prompt_text="$2"
        local input=""
        while [[ -z "$input" ]]; do
            read -p "$prompt_text: " input
            if [[ -z "$input" ]]; then
                echo -e "${RED}❌ This field cannot be empty.${NC}"
            fi
        done
        eval "$var_name=\"\$input\""
    }

    prompt_password() {
        local var_name="$1"
        local prompt_text="$2"
        local input=""
        while true; do
            read -sp "$prompt_text: " input
            echo
            if [[ ${#input} -lt 8 ]]; then
                echo -e "${RED}❌ Password must be at least 8 characters.${NC}"
            else
                break
            fi
        done
        eval "$var_name=\"\$input\""
    }

    echo
    echo -e "${YELLOW}📝 Panel installation configuration:${NC}"
    echo

    # DB config
    prompt panel_db_host "Enter database host" "$panel_db_host"
    prompt panel_db_name "Enter database name" "$panel_db_name"
    prompt panel_db_user "Enter database user" "$panel_db_user"
    echo -e "${BLUE}Generated secure database password automatically.${NC}"

    # Admin account
    echo
    prompt_required user_email "Enter admin email"
    prompt user_username "Enter admin username" "$user_username"
    prompt_required user_firstname "Enter admin first name"
    prompt_required user_lastname "Enter admin last name"
    prompt_password user_password "Enter admin password (min 8 chars)"

    echo
    prompt_required panel_url "Enter Panel URL (e.g., http://$(curl -s ifconfig.me 2>/dev/null || echo 'YOUR_IP'))"
    prompt panel_timezone "Enter Panel timezone" "$panel_timezone"

    # Summary
    echo
    echo -e "${GREEN}✅ Configuration Summary:${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "System User: $INSTALL_USER"
    echo "DB Host: $panel_db_host"
    echo "DB Name: $panel_db_name"
    echo "DB User: $panel_db_user"
    echo "DB Password: (auto-generated)"
    echo "Admin Email: $user_email"
    echo "Admin Username: $user_username"
    echo "Admin Name: $user_firstname $user_lastname"
    echo "Admin Password: (hidden)"
    echo "Panel URL: $panel_url"
    echo "Timezone: $panel_timezone"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    read -p "Continue with installation? (y/n): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo -e "${RED}Installation cancelled.${NC}"
        return
    fi

    # ===================== INSTALL DEPENDENCIES =====================
    echo
    echo -e "${YELLOW}📦 Installing dependencies...${NC}"
    
    # Update system first
    apt update
    DEBIAN_FRONTEND=noninteractive apt -y upgrade
    
    apt -y install software-properties-common curl apt-transport-https ca-certificates gnupg lsb-release sudo
    
    # Add PHP repository
    LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
    
    # Add Redis repository
    curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/redis.list
    
    apt update
    DEBIAN_FRONTEND=noninteractive apt -y install php8.3 php8.3-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip} mariadb-server nginx tar unzip git redis-server
    
    # Install Composer
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

    # ===================== SECURE MARIADB =====================
    echo -e "${YELLOW}🔒 Securing MariaDB...${NC}"
    mysql -u root <<MYSQL_SECURE
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
MYSQL_SECURE

    # ===================== DOWNLOAD PANEL =====================
    echo -e "${YELLOW}📥 Downloading Pterodactyl Panel...${NC}"
    mkdir -p /var/www/pterodactyl
    cd /var/www/pterodactyl || exit 1
    curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
    tar -xzvf panel.tar.gz
    chmod -R 755 storage/* bootstrap/cache/
    rm panel.tar.gz

    # ===================== SETUP DATABASE =====================
    echo -e "${YELLOW}🗄️  Setting up database...${NC}"
    mysql -u root <<MYSQL_SCRIPT
CREATE USER IF NOT EXISTS '${panel_db_user}'@'${panel_db_host}' IDENTIFIED BY '${panel_db_password}';
CREATE DATABASE IF NOT EXISTS ${panel_db_name};
GRANT ALL PRIVILEGES ON ${panel_db_name}.* TO '${panel_db_user}'@'${panel_db_host}' WITH GRANT OPTION;
FLUSH PRIVILEGES;
MYSQL_SCRIPT

    # ===================== PANEL SETUP =====================
    echo -e "${YELLOW}⚙️  Configuring Panel...${NC}"
    cp .env.example .env
    COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader --no-interaction

    php artisan key:generate --force

    # Environment setup with proper input handling
    php artisan p:environment:setup \
        --url="$panel_url" \
        --timezone="$panel_timezone" \
        --cache=redis \
        --session=redis \
        --queue=redis \
        --redis-host=127.0.0.1 \
        --redis-port=6379 \
        --no-interaction

    php artisan p:environment:database \
        --host="$panel_db_host" \
        --port=3306 \
        --database="$panel_db_name" \
        --username="$panel_db_user" \
        --password="$panel_db_password" \
        --no-interaction

    php artisan migrate --seed --force

    # Create admin user
    php artisan p:user:make \
        --email="$user_email" \
        --username="$user_username" \
        --name-first="$user_firstname" \
        --name-last="$user_lastname" \
        --password="$user_password" \
        --admin=1 \
        --no-interaction

    chown -R "$INSTALL_USER":"$INSTALL_USER" /var/www/pterodactyl

    # ===================== SYSTEMD SERVICE FOR PANEL =====================
    echo -e "${YELLOW}🔧 Creating systemd service...${NC}"
    cat <<SERVICE_EOF > /etc/systemd/system/pteroq.service
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service

[Service]
User=$INSTALL_USER
Group=$INSTALL_USER
Restart=always
ExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
SERVICE_EOF

    systemctl daemon-reload
    systemctl enable --now pteroq.service
    systemctl enable --now redis-server

    # ===================== NGINX CONFIG =====================
    echo -e "${YELLOW}🌐 Configuring NGINX...${NC}"
    rm -f /etc/nginx/sites-enabled/default
    
    cat <<NGINX_EOF > /etc/nginx/sites-available/pterodactyl.conf
server {
    listen 80;
    server_name _;

    root /var/www/pterodactyl/public;
    index index.php;

    access_log /var/log/nginx/pterodactyl.app-access.log;
    error_log /var/log/nginx/pterodactyl.app-error.log error;

    client_max_body_size 100m;
    client_body_timeout 120s;

    sendfile off;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
    }

    location ~ /\.ht {
        deny all;
    }
}
NGINX_EOF

    ln -sf /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
    
    if nginx -t; then
        systemctl restart nginx
        echo -e "${GREEN}✅ NGINX configured successfully.${NC}"
    else
        echo -e "${RED}❌ NGINX configuration test failed!${NC}"
        return 1
    fi

    # ===================== CRON JOB =====================
    echo -e "${YELLOW}⏰ Setting up cron job...${NC}"
    (crontab -u "$INSTALL_USER" -l 2>/dev/null; echo "* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1") | crontab -u "$INSTALL_USER" -

    # ===================== SAVE CREDENTIALS =====================
    CREDS_FILE="/root/pterodactyl_credentials.txt"
    cat <<CREDS > "$CREDS_FILE"
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    PTERODACTYL PANEL INSTALLATION CREDENTIALS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Panel URL: $panel_url
Admin Email: $user_email
Admin Username: $user_username
Admin Password: $user_password

Database Host: $panel_db_host
Database Name: $panel_db_name
Database User: $panel_db_user
Database Password: $panel_db_password

System User: $INSTALL_USER

Installation Date: $(date)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
IMPORTANT: Keep this file secure and delete it after 
saving the credentials in a password manager!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
CREDS
    chmod 600 "$CREDS_FILE"

    echo
    echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  ✅ Pterodactyl Panel Installation Complete!  ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${YELLOW}📋 Credentials saved to: ${GREEN}$CREDS_FILE${NC}"
    echo -e "${YELLOW}🌐 Access your panel at: ${GREEN}$panel_url${NC}"
    echo -e "${YELLOW}📧 Admin Email: ${GREEN}$user_email${NC}"
    echo -e "${YELLOW}👤 Admin Username: ${GREEN}$user_username${NC}"
    echo
    echo -e "${RED}⚠️  SECURITY REMINDERS:${NC}"
    echo -e "   1. Set up SSL/HTTPS (use Certbot for Let's Encrypt)"
    echo -e "   2. Configure your firewall (allow ports 80, 443, 8080)"
    echo -e "   3. Delete credentials file after saving: rm $CREDS_FILE"
    echo -e "   4. For AWS: Update Security Group to allow HTTP/HTTPS"
    echo
}

# ===================== WINGS INSTALL =====================
wings_install(){
    echo -e "${GREEN}Starting Wings Installation...${NC}"
    echo
    
    # Get server IP
    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s icanhazip.com 2>/dev/null || echo "127.0.0.1")
    echo -e "${BLUE}Detected Server IP: ${GREEN}$SERVER_IP${NC}"
    
    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}📦 Docker not found. Installing Docker...${NC}"
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        rm get-docker.sh
        
        # Add user to docker group if not root
        if [[ "$INSTALL_USER" != "root" ]]; then
            usermod -aG docker "$INSTALL_USER"
            echo -e "${GREEN}✅ User '$INSTALL_USER' added to docker group${NC}"
        fi
        
        systemctl enable --now docker
        echo -e "${GREEN}✅ Docker installed and started${NC}"
    else
        echo -e "${GREEN}✅ Docker already installed.${NC}"
    fi

    # Enable swap accounting for Docker (recommended for game servers)
    echo -e "${YELLOW}⚙️  Configuring Docker swap accounting...${NC}"
    if ! grep -q "swapaccount=1" /etc/default/grub 2>/dev/null; then
        if [[ -f /etc/default/grub ]]; then
            sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="swapaccount=1 /' /etc/default/grub
            update-grub 2>/dev/null || grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null
            echo -e "${YELLOW}⚠️  Swap accounting enabled. Reboot recommended for this to take effect.${NC}"
        fi
    fi

    # Install Wings
    echo -e "${YELLOW}📥 Downloading Wings...${NC}"
    mkdir -p /etc/pterodactyl
    curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64"
    chmod u+x /usr/local/bin/wings

    # Auto-configure Wings
    echo -e "${YELLOW}⚙️  Auto-configuring Wings for HTTP connection...${NC}"
    
    # Generate a basic Wings configuration
    cat <<WINGS_CONFIG > /etc/pterodactyl/config.yml
debug: false
uuid: CHANGE_ME_UUID
token_id: CHANGE_ME_TOKEN_ID
token: CHANGE_ME_TOKEN
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
allowed_mounts: []
remote: http://${SERVER_IP}
WINGS_CONFIG

    echo
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}⚠️  WINGS NODE CONFIGURATION REQUIRED${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
    echo -e "Wings has been pre-configured with:"
    echo -e "  • Server IP: ${GREEN}$SERVER_IP${NC}"
    echo -e "  • Wings Port: ${GREEN}8080${NC} (HTTP, no SSL)"
    echo -e "  • SFTP Port: ${GREEN}2022${NC}"
    echo
    echo -e "${YELLOW}To complete setup in Pterodactyl Panel:${NC}"
    echo
    echo -e "  1. Log into your ${GREEN}Pterodactyl Panel${NC}"
    echo -e "  2. Go to ${GREEN}Admin → Locations${NC} → Create New Location"
    echo -e "  3. Go to ${GREEN}Admin → Nodes${NC} → Create New Node"
    echo
    echo -e "  ${YELLOW}Node Configuration:${NC}"
    echo -e "     • Name: ${GREEN}Node01${NC} (or any name)"
    echo -e "     • Location: ${GREEN}Select the location you created${NC}"
    echo -e "     • FQDN: ${GREEN}$SERVER_IP${NC}"
    echo -e "     • Communicate Over SSL: ${RED}UNCHECKED ❌${NC}"
    echo -e "     • Behind Proxy: ${RED}UNCHECKED ❌${NC}"
    echo -e "     • Daemon Port: ${GREEN}8080${NC}"
    echo -e "     • Memory: ${GREEN}Enter your VPS RAM (MB)${NC}"
    echo -e "     • Disk: ${GREEN}Enter available disk space (MB)${NC}"
    echo
    echo -e "  4. After creating the node, go to ${GREEN}Configuration${NC} tab"
    echo -e "  5. Copy the ${GREEN}FULL configuration${NC}"
    echo -e "  6. Paste it into: ${GREEN}/etc/pterodactyl/config.yml${NC}"
    echo -e "     Run: ${GREEN}nano /etc/pterodactyl/config.yml${NC}"
    echo
    echo -e "${RED}IMPORTANT:${NC} Make sure to:"
    echo -e "  • Open port ${GREEN}8080${NC} in your firewall/AWS Security Group"
    echo -e "  • Open port ${GREEN}2022${NC} for SFTP"
    echo -e "  • Open port range ${GREEN}25565-25665${NC} for game servers"
    echo
    echo -e "${YELLOW}Press Enter when you've pasted the configuration from Panel...${NC}"
    read

    if [[ ! -f /etc/pterodactyl/config.yml ]]; then
        echo -e "${RED}❌ Configuration file not found at /etc/pterodactyl/config.yml${NC}"
        echo
        echo -e "Manual setup:"
        echo -e "  1. Create the config: ${GREEN}nano /etc/pterodactyl/config.yml${NC}"
        echo -e "  2. Start Wings: ${GREEN}systemctl start wings${NC}"
        echo -e "  3. Check status: ${GREEN}systemctl status wings${NC}"
        echo
        return 1
    fi

    # Verify config has required values
    if grep -q "CHANGE_ME" /etc/pterodactyl/config.yml; then
        echo -e "${RED}❌ Configuration still contains placeholder values!${NC}"
        echo -e "${YELLOW}Please copy the configuration from the Panel and paste it into:${NC}"
        echo -e "${GREEN}/etc/pterodactyl/config.yml${NC}"
        echo
        return 1
    fi

    # Systemd service for Wings
    echo -e "${YELLOW}🔧 Creating Wings service...${NC}"
    cat <<WINGS_SERVICE > /etc/systemd/system/wings.service
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service
PartOf=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
PIDFile=/var/run/wings/daemon.pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
WINGS_SERVICE

    systemctl daemon-reload
    systemctl enable --now wings

    sleep 3

    if systemctl is-active --quiet wings; then
        echo
        echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║     ✅ Wings Installation Completed!          ║${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}"
        echo
        echo -e "${YELLOW}📋 Wings Information:${NC}"
        echo -e "   Server IP: ${GREEN}$SERVER_IP${NC}"
        echo -e "   Wings Port: ${GREEN}8080${NC} (HTTP)"
        echo -e "   SFTP Port: ${GREEN}2022${NC}"
        echo
        echo -e "${YELLOW}Useful Commands:${NC}"
        echo -e "   Check status: ${GREEN}systemctl status wings${NC}"
        echo -e "   View logs: ${GREEN}journalctl -u wings -f${NC}"
        echo -e "   Restart: ${GREEN}systemctl restart wings${NC}"
        echo
        echo -e "${RED}⚠️  Firewall/Security Group Ports to Open:${NC}"
        echo -e "   • 8080 (Wings API)"
        echo -e "   • 2022 (SFTP)"
        echo -e "   • 25565-25665 (Game servers)"
        echo
    else
        echo
        echo -e "${RED}❌ Wings failed to start. Check the logs:${NC}"
        echo -e "${YELLOW}journalctl -u wings -n 50${NC}"
        echo
        echo -e "${YELLOW}Common issues:${NC}"
        echo -e "  • Check if config is properly set: ${GREEN}cat /etc/pterodactyl/config.yml${NC}"
        echo -e "  • Verify Docker is running: ${GREEN}systemctl status docker${NC}"
        echo -e "  • Check Wings logs: ${GREEN}journalctl -u wings -n 100${NC}"
    fi
    echo
}

# ===================== MENU =====================
menu(){
    clear
    banner
    echo
    echo -e "${BLUE}══════════════════════════════════════════════${NC}"
    echo -e "${GREEN}    Pterodactyl Installation Script${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}System User: ${GREEN}$INSTALL_USER${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════${NC}"
    echo "1) Install Panel"
    echo "2) Install Wings"
    echo "3) Install Both (Panel + Wings)"
    echo "4) Exit"
    echo -e "${BLUE}══════════════════════════════════════════════${NC}"
    read -p "Select an option: " opt
    case $opt in
        1) panel_install; echo; read -p "Press Enter to return to menu..."; menu ;;
        2) wings_install; echo; read -p "Press Enter to return to menu..."; menu ;;
        3) panel_install; echo; wings_install; echo; read -p "Press Enter to return to menu..."; menu ;;
        4) echo -e "${GREEN}Goodbye!${NC}"; exit 0 ;;
        *) echo -e "${RED}❌ Invalid option${NC}"; sleep 2; menu ;;
    esac
}

# ===================== ROOT CHECK =====================
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}❌ This script must be run as root${NC}"
   echo -e "${YELLOW}Run with: sudo bash $0${NC}"
   exit 1
fi

# ===================== OS CHECK =====================
if [[ ! -f /etc/lsb-release ]] && [[ ! -f /etc/debian_version ]]; then
    echo -e "${RED}❌ This script only supports Ubuntu/Debian systems${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Running on $(lsb_release -d | cut -f2)${NC}"
echo

menu
