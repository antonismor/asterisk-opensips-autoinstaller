#!/bin/bash
set -e

FG_BLUE="\e[94m"
FG_WHITE="\e[97m"
BOLD="\e[1m"
RESET="\e[0m"
BG_WHITE="\e[47m"
BG_GRAY="\e[100m"
CLEAR_LINE="\e[K"

draw_ui() {
    local title="$1"
    local status="$2"
    local percent="$3"

    clear
    local cols=$(tput cols)
    local width=$((cols - 2))
    [ "$width" -lt 60 ] && width=60

    local horiz_line=$(printf '═%.0s' $(seq 1 "$width"))
    local bar_width=45
    local filled=$(( (percent * bar_width) / 100 ))
    local empty=$(( bar_width - filled ))

    local fill_str=""
    [ "$filled" -gt 0 ] && fill_str=$(printf '%*s' "$filled" "")
    local empty_str=""
    [ "$empty" -gt 0 ] && empty_str=$(printf '%*s' "$empty" "")

    # Top border
    echo -e "${FG_BLUE}╔${horiz_line}╗${CLEAR_LINE}${RESET}"

    # Title row
    local title_pad=$(( width - 2 - ${#title} ))
    [ "$title_pad" -lt 0 ] && title_pad=0
    local title_spaces=$(printf '%*s' "$title_pad" "")
    echo -e "${FG_BLUE}║ ${FG_WHITE}${BOLD}${title}${title_spaces}${FG_BLUE} ║${CLEAR_LINE}${RESET}"

    # Separator
    echo -e "${FG_BLUE}╠${horiz_line}╣${CLEAR_LINE}${RESET}"

    # Status row
    local status_text="Status: $status"
    local pct_text="[ ${percent}%]"
    local status_pad=$(( width - 2 - ${#status_text} - ${#pct_text} ))
    [ "$status_pad" -lt 0 ] && status_pad=0
    local status_spaces=$(printf '%*s' "$status_pad" "")
    echo -e "${FG_BLUE}║ ${FG_WHITE}${status_text}${status_spaces}${pct_text}${FG_BLUE} ║${CLEAR_LINE}${RESET}"

    # Progress bar row
    local bar_pad_left=$(( (width - 2 - bar_width - 2) / 2 ))
    [ "$bar_pad_left" -lt 0 ] && bar_pad_left=0
    local bar_pad_right=$(( width - 2 - bar_width - 2 - bar_pad_left ))
    [ "$bar_pad_right" -lt 0 ] && bar_pad_right=0
    local bar_left_spaces=$(printf '%*s' "$bar_pad_left" "")
    local bar_right_spaces=$(printf '%*s' "$bar_pad_right" "")
    echo -e "${FG_BLUE}║ ${bar_left_spaces}${FG_WHITE}[${BG_WHITE}${fill_str}${RESET}${BG_GRAY}${empty_str}${RESET}${FG_WHITE}]${bar_right_spaces}${FG_BLUE} ║${CLEAR_LINE}${RESET}"

    # Separator
    echo -e "${FG_BLUE}╠${horiz_line}╣${CLEAR_LINE}${RESET}"

    # Footer row
    local footer="Designed and Development By antonios.mortos@outlook.com"
    local footer_pad=$(( (width - 2 - ${#footer}) / 2 ))
    [ "$footer_pad" -lt 0 ] && footer_pad=0
    local footer_pad_right=$(( width - 2 - ${#footer} - footer_pad ))
    [ "$footer_pad_right" -lt 0 ] && footer_pad_right=0
    local footer_left_spaces=$(printf '%*s' "$footer_pad" "")
    local footer_right_spaces=$(printf '%*s' "$footer_pad_right" "")
    echo -e "${FG_BLUE}║ ${footer_left_spaces}${FG_WHITE}${footer}${footer_right_spaces}${FG_BLUE} ║${CLEAR_LINE}${RESET}"

    # Bottom border
    echo -e "${FG_BLUE}╚${horiz_line}╝${CLEAR_LINE}${RESET}"
}

TITLE="OpenSips Web UI Installer"

clear
read -rp "Enter IP for OpenSIPS Control Panel: " SERVER_IP

if [ -z "$SERVER_IP" ]; then
    echo "IP cannot be empty. Exiting."
    exit 1
fi

DB_PASS=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
echo "$DB_PASS" > /root/mysqlpass
chmod 600 /root/mysqlpass

draw_ui "$TITLE" "Installing Web Server, PHP & MariaDB stack" 20
apt-get update -y > /dev/null 2>&1
apt-get install -y apache2 libapache2-mod-php php php-mysql php-gd php-curl php-xml php-pear php-mbstring php-intl php-bcmath php-zip mariadb-server mariadb-client git opensips-mysql-module > /dev/null 2>&1

draw_ui "$TITLE" "Configuring PHP PEAR & database modules" 35
pear channel-update pear.php.net > /dev/null 2>&1 || true
pear install MDB2 > /dev/null 2>&1 || true
pear install MDB2#mysql > /dev/null 2>&1 || true
pear install MDB2_Driver_mysqli > /dev/null 2>&1 || true

systemctl enable apache2 mariadb > /dev/null 2>&1
systemctl start apache2 mariadb > /dev/null 2>&1

draw_ui "$TITLE" "Creating MariaDB database and grant privileges" 50
mysql -e "CREATE DATABASE IF NOT EXISTS opensips;"
mysql -e "CREATE USER IF NOT EXISTS 'opensips'@'localhost' IDENTIFIED BY '${DB_PASS}';"
mysql -e "ALTER USER 'opensips'@'localhost' IDENTIFIED BY '${DB_PASS}';"
mysql -e "GRANT ALL PRIVILEGES ON opensips.* TO 'opensips'@'localhost';"
mysql -e "CREATE USER IF NOT EXISTS 'opensips'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';"
mysql -e "ALTER USER 'opensips'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';"
mysql -e "GRANT ALL PRIVILEGES ON opensips.* TO 'opensips'@'127.0.0.1';"
mysql -e "FLUSH PRIVILEGES;"

draw_ui "$TITLE" "Downloading OpenSIPS Control Panel repository" 65
if [ -d "/var/www/html/opensips-cp" ]; then
    rm -rf /var/www/html/opensips-cp
fi
git clone https://github.com/OpenSIPS/opensips-cp.git /var/www/html/opensips-cp > /dev/null 2>&1

draw_ui "$TITLE" "Importing Control Panel schema to MariaDB" 80
for f in $(find /var/www/html/opensips-cp/ -type f -name "*.mysql" | grep -E "admin|tables|ocp"); do
    mysql -u opensips -p${DB_PASS} opensips < "$f" 2>/dev/null || true
done

find /var/www/html/opensips-cp/config/ -type f -name "*.php" -exec sed -i "s/db_pass = .*/db_pass = '${DB_PASS}';/g" {} + 2>/dev/null || true
find /var/www/html/opensips-cp/config/ -type f -name "*.php" -exec sed -i "s/db_user = .*/db_user = 'opensips';/g" {} + 2>/dev/null || true

chown -R www-data:www-data /var/www/html/opensips-cp
chmod -R 775 /var/www/html/opensips-cp/config

draw_ui "$TITLE" "Configuring Apache VirtualHost & URL routes" 90
cat <<EOF > /etc/apache2/sites-available/opensips-cp.conf
<VirtualHost *:80>
    ServerName ${SERVER_IP}
    DocumentRoot /var/www/html/opensips-cp/web
    <Directory /var/www/html/opensips-cp/web>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
        DirectoryIndex index.php login.php
    </Directory>
    ErrorLog \${APACHE_LOG_DIR}/opensips_cp_error.log
    CustomLog \${APACHE_LOG_DIR}/opensips_cp_access.log combined
</VirtualHost>
EOF

a2dissite 000-default.conf > /dev/null 2>&1 || true
a2ensite opensips-cp.conf > /dev/null 2>&1
a2enmod rewrite > /dev/null 2>&1
systemctl restart apache2 > /dev/null 2>&1

draw_ui "$TITLE" "Web UI installation completed successfully" 100
sleep 1
echo ""
echo "OpenSIPS Control Panel installation complete."
echo "Access URL: http://${SERVER_IP}/"
echo "Default Web User: admin / admin"
echo "Database Password: ${DB_PASS}"
echo "Saved to: /root/mysqlpass"
