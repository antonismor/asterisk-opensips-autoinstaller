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

TITLE="OpenSips Installer"

draw_ui "$TITLE" "Checking Internet connection" 5
if ping -c 2 8.8.8.8 > /dev/null 2>&1; then
    sleep 0.5
else
    echo "Internet Fail"
    exit 1
fi

clear
read -rp "Enter IP for OpenSIPS: " IP

if [ -z "$IP" ]; then
    echo "IP cannot be empty. Exiting."
    exit 1
fi

draw_ui "$TITLE" "Installing system prerequisites & tools" 25
apt-get update -y > /dev/null 2>&1
apt-get install -y curl gnupg2 > /dev/null 2>&1

draw_ui "$TITLE" "Importing OpenSIPS official GPG keys" 45
curl -fsSL https://apt.opensips.org/opensips-org.gpg -o /usr/share/keyrings/opensips-org.gpg

draw_ui "$TITLE" "Configuring OpenSIPS 4.0 apt repository" 65
echo "deb [signed-by=/usr/share/keyrings/opensips-org.gpg] https://apt.opensips.org trixie 4.0-releases" > /etc/apt/sources.list.d/opensips.list

draw_ui "$TITLE" "Installing OpenSIPS 4.0 packages" 85
apt-get update -y > /dev/null 2>&1
apt-get install -y opensips > /dev/null 2>&1

draw_ui "$TITLE" "Applying socket configuration & starting service" 95
sed -i "s/listen=udp:.*:5060/listen=udp:${IP}:5060/g" /etc/opensips/opensips.cfg 2>/dev/null || true
systemctl enable opensips > /dev/null 2>&1
systemctl restart opensips > /dev/null 2>&1

draw_ui "$TITLE" "Installation completed successfully" 100
sleep 1
echo ""
echo "Installation complete. OpenSIPS listening on $IP:5060"
