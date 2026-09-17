#!/bin/bash

BG_BLUE="\e[44m"
FG_WHITE="\e[97m"
FG_RED="\e[91m"
FG_GREEN="\e[92m"
BOLD="\e[1m"
RESET="\e[0m"
CLEAR_LINE="\e[K"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

print_full_line() {
    local text="$1"
    printf "${BG_BLUE}${FG_WHITE}%s${CLEAR_LINE}${RESET}\n" "$text"
}

print_separator() {
    local width=$(tput cols)
    local line=$(printf '─%.0s' $(seq 1 "$width"))
    echo -e "${BG_BLUE}${FG_WHITE}${line}${CLEAR_LINE}${RESET}"
}

print_double_line() {
    local width=$(tput cols)
    local line=$(printf '═%.0s' $(seq 1 "$width"))
    echo -e "${BG_BLUE}${FG_WHITE}${line}${CLEAR_LINE}${RESET}"
}

run_script() {
    local script_name="$1"
    local mode="$2"
    local full_path="${SCRIPT_DIR}/${script_name}"

    if [ ! -f "$full_path" ]; then
        echo -e "${FG_RED}Error: File ${full_path} not found!${RESET}"
        read -rp "Press Enter to continue..."
        return
    fi

    chmod +x "$full_path"
    "$full_path" "$mode"

    read -rp "Press Enter to continue..."
}

draw_menu() {
    clear
    local cols=$(tput cols)
    local inner_width=$((cols - 4))
    [ "$inner_width" -lt 10 ] && inner_width=10

    local top_border=$(printf '═%.0s' $(seq 1 "$((inner_width + 2))"))
    echo -e "${BG_BLUE}${FG_WHITE}${BOLD}╔${top_border}╗${CLEAR_LINE}${RESET}"

    local title="ASTERISK & OPENSIPS CONTROL MENU"
    local pad_left=$(( (inner_width - ${#title}) / 2 ))
    local pad_right=$(( inner_width - ${#title} - pad_left ))
    local spaces_left=$(printf '%*s' "$pad_left" "")
    local spaces_right=$(printf '%*s' "$pad_right" "")

    echo -e "${BG_BLUE}${FG_WHITE}${BOLD}║ ${spaces_left}${title}${spaces_right} ║${CLEAR_LINE}${RESET}"
    echo -e "${BG_BLUE}${FG_WHITE}${BOLD}╚${top_border}╝${CLEAR_LINE}${RESET}"
    echo -e "${BG_BLUE}${CLEAR_LINE}${RESET}"

    print_full_line "  1) Install Asterisk"
    print_full_line "  2) Install Asterisk (Verbose Mode)"
    print_separator

    print_full_line "  3) OpenSIPS Install"
    print_full_line "  4) OpenSIPS Install (Verbose Mode)"
    print_separator

    print_full_line "  5) OpenSIPS Web UI Install"
    print_full_line "  6) OpenSIPS Web UI (Verbose Mode)"
    print_separator

    echo -e "${BG_BLUE}${FG_WHITE}  7) ${FG_RED}${BOLD}[IMPORTANT]${RESET}${BG_BLUE}${FG_WHITE} Upgrade OpenSIPS UI${CLEAR_LINE}${RESET}"
    echo -e "${BG_BLUE}${FG_WHITE}  8) ${FG_RED}${BOLD}[IMPORTANT]${RESET}${BG_BLUE}${FG_WHITE} Upgrade OpenSIPS UI (Verbose Mode)${CLEAR_LINE}${RESET}"
    print_separator

    print_full_line "  9) OpenSIPS Security (fail2ban, iptables, ufw, ipset)"
    print_full_line " 10) OpenSIPS Security (Verbose Mode)"
    print_separator

    print_full_line " 11) Exit"
    echo -e "${BG_BLUE}${CLEAR_LINE}${RESET}"
    print_double_line
    echo ""
}

trap draw_menu SIGWINCH

while true; do
    draw_menu
    echo -ne "${FG_WHITE}${BOLD}Select [1-11]: ${FG_GREEN}"
    read -r opt
    echo -e "${RESET}"

    case $opt in
        1)
            run_script "asterisk.sh" "normal"
            ;;
        2)
            run_script "asterisk.sh" "verbose"
            ;;
        3)
            run_script "opensips.sh" "normal"
            ;;
        4)
            run_script "opensips.sh" "verbose"
            ;;
        5)
            run_script "webui.sh" "normal"
            ;;
        6)
            run_script "webui.sh" "verbose"
            ;;
        7)
            run_script "upgrade.sh" "normal"
            ;;
        8)
            run_script "upgrade.sh" "verbose"
            ;;
        9)
            run_script "security.sh" "normal"
            ;;
        10)
            run_script "security.sh" "verbose"
            ;;
        11)
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo -e "${FG_RED}Invalid option!${RESET}"
            sleep 1
            ;;
    esac
done
