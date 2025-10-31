#!/bin/bash

# Prompt for installation username
read -p "Enter the username to use for installation (e.g., ubuntu, ec2-user): " INSTALL_USER
if [[ -z "$INSTALL_USER" ]]; then
    echo "❌ Username cannot be empty."
    exit 1
fi

# Verify user exists
if ! id "$INSTALL_USER" &>/dev/null; then
    echo "❌ User '$INSTALL_USER' does not exist. Please create it or enter a valid username."
    exit 1
fi

banner(){
cat << "EOF"
 █████  ██████  ███████ ██████   █████   ██████ ████████ ██    ██ ██      ███████ 
██   ██ ██   ██ ██      ██   ██ ██   ██ ██         ██     ██  ██  ██      ██      
███████ ██████  ███████ ██   ██ ███████ ██         ██      ████   ██      █████   
██   ██ ██   ██      ██ ██   ██ ██   ██ ██         ██       ██    ██      ██      
██   ██ ██   ██ ███████ ██████  ██   ██  ██████    ██       ██    ███████ ███████ 
                                                                                  
EOF
}

# ===================== PANEL INSTALL =====================
panel_install(){
    # Default DB values
    panel_db_host="127.0.0.1"
    panel_db_name="panel"
    panel_db_user="arsdactyl"
    panel_db_password="arsdactyl"

    user_email=""
    user_username="$INSTALL_USER"
    user_firstname=""
    user_lastname=""
    user_password=""
    panel_url=""
    panel_timezone="UTC"

    # Prompt functions
    prompt() {
        local var_name="$1"
        local prompt_text="$2"
        local default_value="$3"
        read -p "$prompt_text [$default_value]: " input
        if [[ -n "$input" ]]; then
            eval "$var_name=\"$input\""
        else
            eval "$var_name=\"$default_value\""
        fi
    }

    prompt_required() {
        local var_name="$1"
        local prompt_text="$2"
        local input=""
        while [[ -z "$input" ]]; do
            read -p "$prompt_text: " input
        done
        eval "$var_name=\"$input\""
    }

    prompt_password() {
        local var_name="$1"
        local prompt_text="$2"
        local input=""
        while true; do
            read -sp "$prompt_text: " input
            echo
            if [[ ${#input} -lt 8 ]]; then
                echo "❌ Password must be at least 8 characters."
            else
                break
            fi
        done
        eval "$var_name=\"$input\""
    }

    echo "📝 Panel installation configuration:"

    # DB config
    prompt panel_db_host "Enter database host" "$panel_db_host"
    prompt panel_db_name "Enter database name" "$panel_db_name"
    prompt panel_db_user "Enter database user" "$panel_db_user"
    prompt panel_db_password "Enter database password" "$panel_db_password"

    # Admin account
    prompt_required user_email "Enter admin email"
    prompt_required user_firstname "Enter admin first name"
    prompt_required user_lastname "Enter admin last name"
    prompt_password user_password "Enter admin password (min 8 chars)"

    prompt panel_url "Enter Panel URL (e.g., https://panel.example.com)" "http://127.0.0.1"
    prompt panel_timezone "Enter Panel timezone" "$panel_timezone"

    # Summary
    echo
    echo "✅ Configuration Summary:"
    echo "DB Host: $panel_db_host"
    echo "DB Name: $panel_db_name"
    echo "DB User: $panel_db_user"
    echo "DB Password: (hidden)"
    echo "Admin Email: $user_email"
    echo "Admin Username: $user_username"
    echo "Admin Name: $user_firstname $user_lastname"
    echo "Admin Password: (hidden)"
    echo "Panel URL: $panel_url"
    echo "Timezone: $panel_timezone"

    # Install dependencies
    apt -y install software-properties-common curl apt-transport-https ca-certificates gnupg
    LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
    curl -fsSL https://packages.redis.io/gpg | sudo gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/redis.list
    apt update
    apt -y install php8.3 php8.3-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip} mariadb-server nginx tar unzip git redis-server
    curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer

    # Download Panel
    mkdir -p /var/www/pterodactyl
    cd /var/www/pterodactyl
    curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
    tar -xzvf panel.tar.gz
    chmod -R 755 storage/* bootstrap/cache/

    # Setup database
    mysql -u root <<EOF
CREATE USER '$panel_db_user'@'127.0.0.1' IDENTIFIED BY '$panel_db_password';
CREATE DATABASE $panel_db_name;
GRANT ALL PRIVILEGES ON $panel_db_name.* TO '$panel_db_user'@'127.0.0.1' WITH GRANT OPTION;
EOF

    # Panel setup
    cp .env.example .env
    COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader
    php artisan key:generate --force

    php artisan p:environment:setup <<EOF
$panel_url
$panel_timezone
redis
redis
redis
yes
yes
EOF

    php artisan p:environment:database <<EOF
$panel_db_host
3306
$panel_db_name
$panel_db_user
$panel_db_password
EOF

    php artisan migrate --seed --force

    php artisan p:user:make <<EOF
yes
$user_email
$user_username
$user_firstname
$user_lastname
$user_password
EOF

    chown -R $INSTALL_USER:$INSTALL_USER /var/www/pterodactyl/*

    # Systemd service for panel queue
    SERVICE_FILE="/etc/systemd/system/pteroq.service"
    cat <<EOF > "$SERVICE_FILE"
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
EOF

    systemctl daemon-reload
    systemctl enable --now pteroq.service
    systemctl enable --now redis-server

    # Nginx config
    rm -f /etc/nginx/sites-enabled/default
    CONFIG_FILE="/etc/nginx/sites-available/pterodactyl.conf"

    cat <<EOF > "$CONFIG_FILE"
server {
    listen 80;
    server_name _;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name _;

    root /var/www/pterodactyl/public;

    index index.php;

    access_log /var/log/nginx/pterodactyl.app-access.log;
    error_log /var/log/nginx/pterodactyl.app-error.log error;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
    }

    ssl_certificate /etc/letsencrypt/live/example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;
}
EOF

    ln -s /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
    nginx -t && systemctl restart nginx

    echo "✅ Pterodactyl Panel installation completed."
}

# ===================== WINGS INSTALL =====================
wings_install(){
    read -p "Enter Wings domain for SSL (e.g., panel.example.com): " WINGS_DOMAIN
    mkdir -p /etc/wings
    curl -Lo /etc/wings/wings https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64
    chmod +x /etc/wings/wings

    # Systemd service for Wings
    cat <<EOF > /etc/systemd/system/wings.service
[Unit]
Description=Pterodactyl Wings Daemon
After=network.target

[Service]
User=$INSTALL_USER
Group=$INSTALL_USER
WorkingDirectory=/etc/wings
ExecStart=/etc/wings/wings
Restart=on-failure
StartLimitInterval=600
StartLimitBurst=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now wings
    echo "✅ Wings installation completed."
}

menu(){
    banner
    echo "1) Install Panel"
    echo "2) Install Wings"
    echo "3) Exit"
    read -p "Select an option: " opt
    case $opt in
        1) panel_install ;;
        2) wings_install ;;
        3) exit 0 ;;
        *) echo "❌ Invalid option"; menu ;;
    esac
}

menu
