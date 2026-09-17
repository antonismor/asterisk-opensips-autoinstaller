#!/bin/bash
set -Eeuo pipefail

MODE="${1:-normal}"
TITLE="OPENSIPS CLEAN INSTALLER & HARDENED SECURITY v2.3.0"
BACKUP_ROOT="/root/orama-opensips-security-backups"
CONFIG_FILE="/etc/opensips/opensips.cfg"
SECURITY_INCLUDE="/etc/opensips/orama-security-route.cfg"
NFT_DIR="/etc/nftables.d"
NFT_FILE="${NFT_DIR}/orama-opensips.nft"
F2B_REGISTER_FILTER="/etc/fail2ban/filter.d/orama-opensips-register.conf"
F2B_SCANNER_FILTER="/etc/fail2ban/filter.d/orama-opensips-scanner.conf"
F2B_FLOOD_FILTER="/etc/fail2ban/filter.d/orama-opensips-flood.conf"
F2B_JAIL="/etc/fail2ban/jail.d/orama-opensips.local"
F2B_LOCAL="/etc/fail2ban/fail2ban.local"
RSYSLOG_FILE="/etc/rsyslog.d/31-orama-opensips-security.conf"
LOG_FILE="/var/log/opensips-security.log"
SYSCTL_FILE="/etc/sysctl.d/99-orama-opensips-security.conf"
BAN_12_MONTHS=31536000
BAN_FLOOD=604800
DB_PURGE_AGE=34560000
SIP_PORT_DEFAULT=51978
MANAGEMENT_LAN="10.11.100.0/24"
PROVIDER_DEFAULT="176.12.105.210/32"
OPENSIPS_DEFAULTS="/etc/default/opensips"
S_MEMORY_DEFAULT=128
P_MEMORY_DEFAULT=32
OPEN_FILES_LIMIT=65535

FG_BLUE="\e[94m"
FG_WHITE="\e[97m"
FG_GREEN="\e[92m"
FG_YELLOW="\e[93m"
FG_RED="\e[91m"
BOLD="\e[1m"
RESET="\e[0m"
BG_WHITE="\e[47m"
BG_GRAY="\e[100m"
CLEAR_LINE="\e[K"

LAST_BACKUP=""

draw_ui() {
    [ "$MODE" = "verbose" ] && return 0
    local title="$1"
    local status="$2"
    local percent="$3"
    clear || true
    local cols
    cols=$(tput cols 2>/dev/null || echo 100)
    local width=$((cols - 2))
    [ "$width" -lt 78 ] && width=78
    local horiz_line
    horiz_line=$(printf '═%.0s' $(seq 1 "$width"))
    local bar_width=45
    local filled=$(( (percent * bar_width) / 100 ))
    local empty=$(( bar_width - filled ))
    local fill_str=""
    local empty_str=""
    [ "$filled" -gt 0 ] && fill_str=$(printf '%*s' "$filled" "")
    [ "$empty" -gt 0 ] && empty_str=$(printf '%*s' "$empty" "")
    echo -e "${FG_BLUE}╔${horiz_line}╗${CLEAR_LINE}${RESET}"
    local title_pad=$(( width - 2 - ${#title} ))
    [ "$title_pad" -lt 0 ] && title_pad=0
    printf "${FG_BLUE}║ ${FG_WHITE}${BOLD}%s%*s${FG_BLUE} ║${CLEAR_LINE}${RESET}\n" "$title" "$title_pad" ""
    echo -e "${FG_BLUE}╠${horiz_line}╣${RESET}"
    local status_text="Status: $status"
    local pct_text="[ ${percent}%]"
    local status_pad=$(( width - 2 - ${#status_text} - ${#pct_text} ))
    [ "$status_pad" -lt 0 ] && status_pad=0
    printf "${FG_BLUE}║ ${FG_WHITE}%s%*s%s${FG_BLUE} ║${CLEAR_LINE}${RESET}\n" "$status_text" "$status_pad" "" "$pct_text"
    local bar_pad_left=$(( (width - 2 - bar_width - 2) / 2 ))
    [ "$bar_pad_left" -lt 0 ] && bar_pad_left=0
    local bar_pad_right=$(( width - 2 - bar_width - 2 - bar_pad_left ))
    [ "$bar_pad_right" -lt 0 ] && bar_pad_right=0
    printf "${FG_BLUE}║ %*s${FG_WHITE}[${BG_WHITE}%s${RESET}${BG_GRAY}%s${RESET}${FG_WHITE}]%*s${FG_BLUE} ║${CLEAR_LINE}${RESET}\n" \
        "$bar_pad_left" "" "$fill_str" "$empty_str" "$bar_pad_right" ""
    echo -e "${FG_BLUE}╠${horiz_line}╣${RESET}"
    local footer="Designed and Development By antonios.mortos@outlook.com"
    local footer_pad=$(( (width - 2 - ${#footer}) / 2 ))
    [ "$footer_pad" -lt 0 ] && footer_pad=0
    local footer_right=$(( width - 2 - ${#footer} - footer_pad ))
    [ "$footer_right" -lt 0 ] && footer_right=0
    printf "${FG_BLUE}║ %*s${FG_WHITE}%s%*s${FG_BLUE} ║${CLEAR_LINE}${RESET}\n" "$footer_pad" "" "$footer" "$footer_right" ""
    echo -e "${FG_BLUE}╚${horiz_line}╝${RESET}"
}

msg() {
    echo -e "${FG_BLUE}[INFO]${RESET} $*"
}

ok() {
    echo -e "${FG_GREEN}[OK]${RESET} $*"
}

warn() {
    echo -e "${FG_YELLOW}[WARN]${RESET} $*"
}

die() {
    echo -e "${FG_RED}[ERROR]${RESET} $*" >&2
    exit 1
}

run_cmd() {
    if [ "$MODE" = "verbose" ]; then
        echo -e "\n${BOLD}>>> $*${RESET}"
        "$@"
    else
        "$@" >/dev/null 2>&1
    fi
}

restore_backup() {
    local backup="$1"
    [ -d "$backup" ] || die "Backup directory not found: $backup"
    msg "Restoring backup: $backup"
    [ -f "$backup/opensips.cfg" ] && cp -a "$backup/opensips.cfg" "$CONFIG_FILE"
    [ -f "$backup/nftables.conf" ] && cp -a "$backup/nftables.conf" /etc/nftables.conf
    if [ -f "$backup/orama-opensips.nft" ]; then
        mkdir -p "$NFT_DIR"
        cp -a "$backup/orama-opensips.nft" "$NFT_FILE"
    else
        rm -f "$NFT_FILE"
    fi
    [ -f "$backup/orama-security-route.cfg" ] && cp -a "$backup/orama-security-route.cfg" "$SECURITY_INCLUDE"
    [ -f "$backup/orama-opensips.local" ] && cp -a "$backup/orama-opensips.local" "$F2B_JAIL"
    [ -f "$backup/orama-opensips-register.conf" ] && cp -a "$backup/orama-opensips-register.conf" "$F2B_REGISTER_FILTER"
    [ -f "$backup/orama-opensips-scanner.conf" ] && cp -a "$backup/orama-opensips-scanner.conf" "$F2B_SCANNER_FILTER"
    [ -f "$backup/orama-opensips-flood.conf" ] && cp -a "$backup/orama-opensips-flood.conf" "$F2B_FLOOD_FILTER"
    [ -f "$backup/fail2ban.local" ] && cp -a "$backup/fail2ban.local" "$F2B_LOCAL"
    [ -f "$backup/31-orama-opensips-security.conf" ] && cp -a "$backup/31-orama-opensips-security.conf" "$RSYSLOG_FILE"
    [ -f "$backup/99-orama-opensips-security.conf" ] && cp -a "$backup/99-orama-opensips-security.conf" "$SYSCTL_FILE"
    [ -f "$backup/opensips.default" ] && cp -a "$backup/opensips.default" "$OPENSIPS_DEFAULTS"
    sysctl --system >/dev/null 2>&1 || true
    systemctl restart rsyslog >/dev/null 2>&1 || true
    systemctl restart nftables >/dev/null 2>&1 || true
    systemctl restart fail2ban >/dev/null 2>&1 || true
    if [ -f "$CONFIG_FILE" ]; then
        if opensips -C -f "$CONFIG_FILE" >/dev/null 2>&1; then
            systemctl restart opensips >/dev/null 2>&1 || true
        else
            warn "Restored OpenSIPS config does not validate. OpenSIPS was not restarted."
        fi
    fi
    ok "Rollback completed."
    exit 0
}

trap 'rc=$?; if [ $rc -ne 0 ]; then echo -e "\n${FG_RED}[FAILED]${RESET} Security hardening stopped with code $rc."; [ -n "${LAST_BACKUP:-}" ] && echo "Backup available at: $LAST_BACKUP"; fi' EXIT

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    die "Run as root: sudo bash $0"
fi

if [ "${1:-}" = "--rollback" ]; then
    target="${2:-latest}"
    if [ "$target" = "latest" ]; then
        target=$(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | tail -n 1 || true)
        [ -n "$target" ] || die "No backup found under $BACKUP_ROOT"
    fi
    restore_backup "$target"
fi

if [ "$MODE" != "normal" ] && [ "$MODE" != "verbose" ]; then
    MODE="normal"
fi

[ -f "$CONFIG_FILE" ] || die "OpenSIPS config not found: $CONFIG_FILE"
command -v opensips >/dev/null 2>&1 || die "opensips binary not found."

clear || true
if [ "$MODE" = "verbose" ]; then
    echo "=================================================================="
    echo " OPENSIPS CLEAN INSTALLER & HARDENED SECURITY v2.3.0 - VERBOSE"
    echo "=================================================================="
fi

read -rp "OpenSIPS IP [10.11.101.252]: " OPENSIPS_IP
OPENSIPS_IP="${OPENSIPS_IP:-10.11.101.252}"

ASTERISK_IP="10.11.101.251"

read -rp "SIP port [${SIP_PORT_DEFAULT}]: " SIP_PORT
SIP_PORT="${SIP_PORT:-$SIP_PORT_DEFAULT}"

read -rp "Provider IPv4/CIDR list [${PROVIDER_DEFAULT}] (type PUBLIC for public rate-limited SIP): " PROVIDER_INPUT
PROVIDER_INPUT="${PROVIDER_INPUT// /}"
if [ -z "$PROVIDER_INPUT" ]; then
    PROVIDER_INPUT="$PROVIDER_DEFAULT"
elif [ "${PROVIDER_INPUT^^}" = "PUBLIC" ]; then
    PROVIDER_INPUT=""
fi

[[ "$SIP_PORT" =~ ^[0-9]+$ ]] || die "Invalid SIP port."
[ "$SIP_PORT" -ge 1 ] && [ "$SIP_PORT" -le 65535 ] || die "Invalid SIP port."

python3 - "$OPENSIPS_IP" "$ASTERISK_IP" "$PROVIDER_INPUT" <<'PY'
import ipaddress, sys
try:
    ipaddress.ip_address(sys.argv[1])
    ipaddress.ip_address(sys.argv[2])
    if sys.argv[3]:
        for item in sys.argv[3].split(","):
            n=ipaddress.ip_network(item, strict=False)
            if n.version != 4:
                raise ValueError("provider list must be IPv4/CIDR")
except Exception as e:
    print(f"Invalid IP/CIDR input: {e}", file=sys.stderr)
    raise SystemExit(1)
PY

if ! ip -4 -o addr show | awk '{print $4}' | cut -d/ -f1 | grep -Fxq "$OPENSIPS_IP"; then
    die "OpenSIPS IP $OPENSIPS_IP is not configured on this server."
fi

# Strict management trust: ONLY localhost and the real management subnet.
# Do not broaden this to 10.11.100.0/22 or include adjacent /24 networks.
TRUSTED_CIDRS=(
    "127.0.0.1/32"
    "$MANAGEMENT_LAN"
)

if [ -n "$PROVIDER_INPUT" ]; then
    IFS=',' read -r -a PROVIDERS <<< "$PROVIDER_INPUT"
    SIP_MODE="PROVIDER-ALLOWLIST"
else
    PROVIDERS=()
    SIP_MODE="PUBLIC-RATELIMITED"
fi

normalize_ipv4_cidrs() {
    python3 - "$@" <<'PYNET'
import ipaddress
import sys
nets = [ipaddress.ip_network(x, strict=False) for x in sys.argv[1:]]
for net in ipaddress.collapse_addresses(nets):
    print(net)
PYNET
}

# nftables interval sets reject overlapping entries. Collapse duplicates,
# hosts contained in LAN CIDRs and adjacent/overlapping networks first.
# Keep the security ignore-list normalized, but DO NOT use the collapsed list
# for differentiated firewall privileges.  Management and PBX trust are kept
# as explicit non-overlapping sets.
mapfile -t TRUSTED_CIDRS < <(normalize_ipv4_cidrs "${TRUSTED_CIDRS[@]}")
if [ "${#PROVIDERS[@]}" -gt 0 ]; then
    mapfile -t PROVIDERS < <(normalize_ipv4_cidrs "${PROVIDERS[@]}")
fi

# Full host access to OpenSIPS is intentionally limited to:
#   - Management LAN 10.11.100.0/24
#   - The Asterisk/PBX host 10.11.101.251/32
# This guarantees PBX <-> OpenSIPS communication and management from 10.11.100.0/24.
FULL_ACCESS_CIDRS=(
    "$MANAGEMENT_LAN"
    "${ASTERISK_IP}/32"
)
mapfile -t FULL_ACCESS_CIDRS < <(normalize_ipv4_cidrs "${FULL_ACCESS_CIDRS[@]}")

join_comma() {
    local IFS=", "
    echo "$*"
}

TRUSTED_NFT=$(join_comma "${TRUSTED_CIDRS[@]}")
TRUSTED_F2B="${TRUSTED_CIDRS[*]}"
FULL_ACCESS_NFT=$(join_comma "${FULL_ACCESS_CIDRS[@]}")
PROVIDERS_NFT=""
PROVIDERS_F2B=""
if [ "${#PROVIDERS[@]}" -gt 0 ]; then
    PROVIDERS_NFT=$(join_comma "${PROVIDERS[@]}")
    PROVIDERS_F2B="${PROVIDERS[*]}"
fi

draw_ui "$TITLE" "Creating full rollback backup" 8
STAMP=$(date +%Y%m%d-%H%M%S)
LAST_BACKUP="${BACKUP_ROOT}/${STAMP}"
mkdir -p "$LAST_BACKUP"
cp -a "$CONFIG_FILE" "$LAST_BACKUP/opensips.cfg"
[ -f /etc/nftables.conf ] && cp -a /etc/nftables.conf "$LAST_BACKUP/nftables.conf"
[ -f "$NFT_FILE" ] && cp -a "$NFT_FILE" "$LAST_BACKUP/orama-opensips.nft"
[ -f "$SECURITY_INCLUDE" ] && cp -a "$SECURITY_INCLUDE" "$LAST_BACKUP/orama-security-route.cfg"
[ -f "$F2B_JAIL" ] && cp -a "$F2B_JAIL" "$LAST_BACKUP/orama-opensips.local"
[ -f "$F2B_REGISTER_FILTER" ] && cp -a "$F2B_REGISTER_FILTER" "$LAST_BACKUP/orama-opensips-register.conf"
[ -f "$F2B_SCANNER_FILTER" ] && cp -a "$F2B_SCANNER_FILTER" "$LAST_BACKUP/orama-opensips-scanner.conf"
[ -f "$F2B_FLOOD_FILTER" ] && cp -a "$F2B_FLOOD_FILTER" "$LAST_BACKUP/orama-opensips-flood.conf"
[ -f "$F2B_LOCAL" ] && cp -a "$F2B_LOCAL" "$LAST_BACKUP/fail2ban.local"
[ -f "$RSYSLOG_FILE" ] && cp -a "$RSYSLOG_FILE" "$LAST_BACKUP/31-orama-opensips-security.conf"
[ -f "$SYSCTL_FILE" ] && cp -a "$SYSCTL_FILE" "$LAST_BACKUP/99-orama-opensips-security.conf"
[ -f "$OPENSIPS_DEFAULTS" ] && cp -a "$OPENSIPS_DEFAULTS" "$LAST_BACKUP/opensips.default"

draw_ui "$TITLE" "Installing nftables, Fail2Ban, rsyslog and security tools" 18
run_cmd apt-get update
DEBIAN_FRONTEND=noninteractive run_cmd apt-get install -y nftables fail2ban rsyslog curl ca-certificates python3

if command -v ufw >/dev/null 2>&1; then
    ufw --force disable >/dev/null 2>&1 || true
fi
systemctl disable --now ufw.service >/dev/null 2>&1 || true
systemctl disable --now netfilter-persistent.service >/dev/null 2>&1 || true
DEBIAN_FRONTEND=noninteractive apt-get purge -y ufw iptables-persistent netfilter-persistent >/dev/null 2>&1 || true

draw_ui "$TITLE" "Applying kernel anti-spoofing and TCP hardening" 30
cat > "$SYSCTL_FILE" <<'EOF'
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 16384
net.ipv4.tcp_synack_retries = 3
net.core.somaxconn = 4096
net.core.netdev_max_backlog = 65536
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
EOF
run_cmd sysctl --system

draw_ui "$TITLE" "Building nftables host firewall and SIP kernel shield" 44
mkdir -p "$NFT_DIR"

if [ -n "$PROVIDERS_NFT" ]; then
    cat > "$NFT_FILE" <<EOF
table inet orama_opensips {
    set trusted4 {
        type ipv4_addr
        flags interval
        elements = { ${TRUSTED_NFT} }
    }

    set fullaccess4 {
        type ipv4_addr
        flags interval
        elements = { ${FULL_ACCESS_NFT} }
    }

    set providers4 {
        type ipv4_addr
        flags interval
        elements = { ${PROVIDERS_NFT} }
    }

    chain input {
        type filter hook input priority 0; policy drop;

        iifname "lo" accept
        ct state invalid counter drop
        ct state established,related accept

        # Explicit internal trust: management LAN and Asterisk/PBX may reach
        # every local service on this OpenSIPS host. Internet sources never match this set.
        ip saddr @fullaccess4 accept

        ip protocol icmp icmp type { destination-unreachable, time-exceeded, parameter-problem } accept
        ip protocol icmp icmp type echo-request limit rate 2/second burst 4 packets accept
        meta l4proto ipv6-icmp accept

        ip saddr @trusted4 tcp dport { 22, 80, 443 } accept
        ip saddr @trusted4 udp dport ${SIP_PORT} accept
        ip saddr @trusted4 tcp dport ${SIP_PORT} accept

        ip saddr @providers4 udp dport ${SIP_PORT} accept
        ip saddr @providers4 tcp dport ${SIP_PORT} accept

        limit rate 5/minute burst 10 packets log prefix "ORAMA-DROP " level warn
        counter drop
    }

    chain forward {
        type filter hook forward priority 0; policy drop;
    }

    chain output {
        type filter hook output priority 0; policy accept;
    }
}
EOF
else
    cat > "$NFT_FILE" <<EOF
table inet orama_opensips {
    set trusted4 {
        type ipv4_addr
        flags interval
        elements = { ${TRUSTED_NFT} }
    }

    set fullaccess4 {
        type ipv4_addr
        flags interval
        elements = { ${FULL_ACCESS_NFT} }
    }

    chain input {
        type filter hook input priority 0; policy drop;

        iifname "lo" accept
        ct state invalid counter drop
        ct state established,related accept

        # Explicit internal trust: management LAN and Asterisk/PBX may reach
        # every local service on this OpenSIPS host. Internet sources never match this set.
        ip saddr @fullaccess4 accept

        ip protocol icmp icmp type { destination-unreachable, time-exceeded, parameter-problem } accept
        ip protocol icmp icmp type echo-request limit rate 2/second burst 4 packets accept
        meta l4proto ipv6-icmp accept

        ip saddr @trusted4 tcp dport { 22, 80, 443 } accept
        ip saddr @trusted4 udp dport ${SIP_PORT} accept
        ip saddr @trusted4 tcp dport ${SIP_PORT} accept

        udp dport ${SIP_PORT} limit rate 300/second burst 600 packets accept
        tcp dport ${SIP_PORT} tcp flags & (fin|syn|rst|ack) == syn limit rate 100/second burst 200 packets accept

        limit rate 5/minute burst 10 packets log prefix "ORAMA-DROP " level warn
        counter drop
    }

    chain forward {
        type filter hook forward priority 0; policy drop;
    }

    chain output {
        type filter hook output priority 0; policy accept;
    }
}
EOF
fi

[ -f /etc/nftables.conf ] || cat > /etc/nftables.conf <<'EOF'
#!/usr/sbin/nft -f
flush ruleset
EOF

if ! grep -Eq '^[[:space:]]*include[[:space:]]+"/etc/nftables\.d/\*\.nft"' /etc/nftables.conf; then
    echo 'include "/etc/nftables.d/*.nft"' >> /etc/nftables.conf
fi

nft -c -f /etc/nftables.conf || {
    if [ -f "$LAST_BACKUP/nftables.conf" ]; then
        cp -a "$LAST_BACKUP/nftables.conf" /etc/nftables.conf
    else
        rm -f /etc/nftables.conf
    fi
    if [ -f "$LAST_BACKUP/orama-opensips.nft" ]; then
        cp -a "$LAST_BACKUP/orama-opensips.nft" "$NFT_FILE"
    else
        rm -f "$NFT_FILE"
    fi
    die "nftables validation failed. Original nftables state restored."
}

run_cmd systemctl enable nftables

draw_ui "$TITLE" "Configuring OpenSIPS security event logging" 54
cat > "$RSYSLOG_FILE" <<EOF
:msg, contains, "ORAMA_SECURITY" ${LOG_FILE}
EOF

touch "$LOG_FILE"
chown syslog:adm "$LOG_FILE" 2>/dev/null || true
chmod 0640 "$LOG_FILE"
run_cmd systemctl enable rsyslog
run_cmd systemctl restart rsyslog

cat > /etc/logrotate.d/orama-opensips-security <<EOF
${LOG_FILE} {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 0640 syslog adm
    postrotate
        systemctl kill -s HUP rsyslog.service >/dev/null 2>&1 || true
    endscript
}
EOF

draw_ui "$TITLE" "Applying OpenSIPS runtime memory and startup settings" 60
if [ -f "$OPENSIPS_DEFAULTS" ]; then
    if grep -q '^RUN_OPENSIPS=' "$OPENSIPS_DEFAULTS"; then
        sed -i 's/^RUN_OPENSIPS=.*/RUN_OPENSIPS=yes/' "$OPENSIPS_DEFAULTS"
    else
        echo 'RUN_OPENSIPS=yes' >> "$OPENSIPS_DEFAULTS"
    fi

    if grep -q '^S_MEMORY=' "$OPENSIPS_DEFAULTS"; then
        sed -i "s/^S_MEMORY=.*/S_MEMORY=${S_MEMORY_DEFAULT}/" "$OPENSIPS_DEFAULTS"
    else
        echo "S_MEMORY=${S_MEMORY_DEFAULT}" >> "$OPENSIPS_DEFAULTS"
    fi

    if grep -q '^P_MEMORY=' "$OPENSIPS_DEFAULTS"; then
        sed -i "s/^P_MEMORY=.*/P_MEMORY=${P_MEMORY_DEFAULT}/" "$OPENSIPS_DEFAULTS"
    else
        echo "P_MEMORY=${P_MEMORY_DEFAULT}" >> "$OPENSIPS_DEFAULTS"
    fi
else
    cat > "$OPENSIPS_DEFAULTS" <<EOF
RUN_OPENSIPS=yes
USER=opensips
GROUP=opensips
S_MEMORY=${S_MEMORY_DEFAULT}
P_MEMORY=${P_MEMORY_DEFAULT}
DUMP_CORE=no
OPTIONS=""
EOF
fi

draw_ui "$TITLE" "Injecting non-destructive OpenSIPS PIKE and REGISTER guard" 66
if [ "$SIP_MODE" = "PUBLIC-RATELIMITED" ]; then
    cat > "$SECURITY_INCLUDE" <<'EOF'
if (is_method("REGISTER")) {
    xlog("L_WARN", "ORAMA_SECURITY REGISTER_ATTACK IP=$si PROTO=$socket_in(proto) UA=$ua\n");
    sl_send_reply(403, "Forbidden");
    exit;
}

if ($(ua{s.tolower}) =~ "(sipvicious|friendly-scanner|sundayddos|vaxsipuseragent|sipcli|pplsip|sipsak)") {
    xlog("L_WARN", "ORAMA_SECURITY SCANNER_ATTACK IP=$si PROTO=$socket_in(proto) UA=$ua\n");
    sl_send_reply(403, "Forbidden");
    exit;
}

if (!pike_check_req()) {
    xlog("L_WARN", "ORAMA_SECURITY PIKE_FLOOD IP=$si PROTO=$socket_in(proto) UA=$ua\n");
    exit;
}
EOF
else
    cat > "$SECURITY_INCLUDE" <<'EOF'
if (is_method("REGISTER")) {
    xlog("L_WARN", "ORAMA_SECURITY REGISTER_ATTACK IP=$si PROTO=$socket_in(proto) UA=$ua\n");
    sl_send_reply(403, "Forbidden");
    exit;
}

if ($(ua{s.tolower}) =~ "(sipvicious|friendly-scanner|sundayddos|vaxsipuseragent|sipcli|pplsip|sipsak)") {
    xlog("L_WARN", "ORAMA_SECURITY SCANNER_ATTACK IP=$si PROTO=$socket_in(proto) UA=$ua\n");
    sl_send_reply(403, "Forbidden");
    exit;
}
EOF
fi

python3 - "$CONFIG_FILE" "$SECURITY_INCLUDE" "$(opensips -V 2>/dev/null | head -n 1 || true)" "$OPENSIPS_IP" "$SIP_PORT" "$OPEN_FILES_LIMIT" <<'PY'
from pathlib import Path
import re, sys

cfg_path = Path(sys.argv[1])
include_path = sys.argv[2]
runtime_version = sys.argv[3].strip() or "unknown"
opensips_ip = sys.argv[4]
sip_port = int(sys.argv[5])
open_files_limit = int(sys.argv[6])
cfg = cfg_path.read_text()

# Clean up the invalid legacy line injected by older hardening revisions.
# xlog() is a core function in OpenSIPS 4.x; there is no xlog.so to load.
cfg = re.sub(r'(?m)^[ \t]*loadmodule[ \t]+"(?:[^"\n]*/)?xlog\.so"[ \t]*\n?', '', cfg)

# Force exactly one managed UDP listener so OpenSIPS and nftables always use
# the same address/port. Remove legacy UDP socket/listen directives first.
cfg = re.sub(
    r'(?m)^[ \t]*(?:socket|listen)[ \t]*=[ \t]*udp:[^\n]*(?:\n|$)',
    '',
    cfg,
)
managed_socket = f"socket=udp:{opensips_ip}:{sip_port}"

# Normalize open_files_limit and remove duplicate active declarations.
cfg = re.sub(r'(?m)^[ \t]*open_files_limit[ \t]*=[^\n]*(?:\n|$)', '', cfg)

# Insert managed core parameters before the first module/route directive.
anchor = re.search(r'(?m)^[ \t]*(?:loadmodule|route[ \t]*\{)', cfg)
pos = anchor.start() if anchor else 0
core_block = (
    f"open_files_limit={open_files_limit}\n"
    f"{managed_socket}\n"
)
cfg = cfg[:pos] + core_block + cfg[pos:]

# Ensure core xlog verbosity is explicitly configured.
if not re.search(r'(?m)^[ \t]*xlog_level[ \t]*=', cfg):
    m = re.search(r'(?m)^[ \t]*log_level[ \t]*=.*$', cfg)
    if m:
        cfg = cfg[:m.end()] + '\nxlog_level=2' + cfg[m.end():]
    else:
        m = re.search(r'(?m)^[ \t]*(?:loadmodule|route[ \t]*\{)', cfg)
        pos = m.start() if m else 0
        cfg = cfg[:pos] + 'xlog_level=2\n' + cfg[pos:]

include_line = f'include_file "{include_path}"'
if include_line not in cfg:
    main = re.search(r'(?m)^[ \t]*route[ \t]*\{[ \t]*(?:#.*)?$', cfg)
    if not main:
        raise SystemExit("Main 'route {' block not found in opensips.cfg")
    cfg = cfg[:main.end()] + "\n    " + include_line + cfg[main.end():]

main = re.search(r'(?m)^[ \t]*route[ \t]*\{[ \t]*(?:#.*)?$', cfg)
if not main:
    raise SystemExit("Main route block not found after include injection")

insert_at = main.start()
module_lines = []

# Security runtime modules only. Other modules are catalogued below and are not
# blindly enabled: many need DB URLs, external daemons/SDKs, certificates,
# hardware or mutually-selectable backends.
for module in ("sl.so", "pike.so", "proto_udp.so"):
    pat = rf'(?m)^[ \t]*loadmodule[ \t]+"(?:[^"]*/)?{re.escape(module)}"[ \t]*$'
    if not re.search(pat, cfg):
        module_lines.append(f'loadmodule "{module}"')

pike_params = [
    ('sampling_time_unit', '2'),
    ('reqs_density_per_unit', '20'),
    ('remove_latency', '120'),
]
for name, value in pike_params:
    pat = rf'(?m)^[ \t]*modparam\([ \t]*"pike"[ \t]*,[ \t]*"{re.escape(name)}"'
    if not re.search(pat, cfg):
        module_lines.append(f'modparam("pike", "{name}", {value})')

if module_lines:
    block = "\n#### ORAMA SECURITY MODULES - managed by hardening script ####\n"
    block += "\n".join(module_lines)
    block += "\n#### END ORAMA SECURITY MODULES ####\n\n"
    cfg = cfg[:insert_at] + block + cfg[insert_at:]

# Official OpenSIPS 4.1/devel module inventory from docs.opensips.org/manual/4-1/modules/.
# Every documented module is represented in opensips.cfg. Modules already loaded
# elsewhere are marked ACTIVE. Others are intentionally left commented until their
# mandatory DB/external-service/TLS/hardware configuration exists.
catalog = {
    "SIP SIGNALING": [
        "b2b_entities.so","b2b_logic.so","call_center.so","dialog.so","nat_traversal.so",
        "nathelper.so","options.so","registrar.so","signaling.so","uac_registrant.so",
        "tm.so","sl.so","media_exchange.so","callops.so","b2b_sdp_demux.so","msrp_ua.so"
    ],
    "SIP ROUTING": [
        "carrierroute.so","cpl_c.so","dispatcher.so","drouting.so","qrouting.so","emergency.so",
        "enum.so","jabber.so","imc.so","load_balancer.so","mid_registrar.so","msilo.so",
        "msrp_gateway.so","rr.so","script_helper.so","osp.so"
    ],
    "SIP MESSAGE OPERATIONS": [
        "compression.so","diversion.so","identity.so","maxfwd.so","mangler.so","path.so",
        "sip_i.so","sipmsgops.so","stir_shaken.so","topology_hiding.so","uac.so","uac_auth.so",
        "uac_redirect.so","sst.so"
    ],
    "SIP PRESENCE": [
        "presence.so","presence_callinfo.so","presence_dialoginfo.so","presence_dfks.so",
        "presence_mwi.so","presence_reginfo.so","presence_xcapdiff.so","presence_xml.so","pua.so",
        "pua_bla.so","pua_dialoginfo.so","pua_mi.so","pua_reginfo.so","pua_usrloc.so","pua_xmpp.so",
        "b2b_sca.so","rls.so","xcap.so","xcap_client.so"
    ],
    "SCRIPT HELPERS": [
        "json.so","xml.so","cfgutils.so","config.so","exec.so","textops.so","sqlops.so","regex.so",
        "mathops.so","benchmark.so","gflags.so","python.so","lua.so","perl.so","mmgeoip.so","uuid.so","mqueue.so"
    ],
    "AUTH": [
        "auth_aaa.so","auth.so","auth_db.so","auth_jwt.so","auth_aka.so","auth_web3.so",
        "aka_av_diameter.so","permissions.so"
    ],
    "ACCOUNTING AND BILLING": ["acc.so","call_control.so","cgrates.so"],
    "DIALPLAN": [
        "alias_db.so","dialplan.so","domain.so","domainpolicy.so","group.so","userblacklist.so",
        "speeddial.so","peering.so"
    ],
    "DATA CACHING": ["dns_cache.so","rate_cacher.so","sql_cacher.so","trie.so","usrloc.so"],
    "TRAFFIC SHAPING": ["pike.so","qos.so","ratelimit.so","fraud_detection.so"],
    "SQL DATABASE": [
        "db_berkeley.so","db_cachedb.so","db_flatstore.so","db_http.so","db_mysql.so","db_oracle.so",
        "db_perlvdb.so","db_postgres.so","db_sqlite.so","db_text.so","db_unixodbc.so","db_virtual.so"
    ],
    "NOSQL CACHE DATABASE": [
        "cachedb_cassandra.so","cachedb_couchbase.so","cachedb_dynamodb.so","cachedb_local.so",
        "cachedb_memcached.so","cachedb_mongodb.so","cachedb_redis.so","cachedb_sql.so"
    ],
    "OPENSIPS API AND EVENTS": [
        "event_datagram.so","event_flatstore.so","event_kafka.so","event_routing.so","event_rabbitmq.so",
        "event_stream.so","event_sqs.so","event_virtual.so","event_xmlrpc.so","mi_datagram.so","mi_fifo.so",
        "mi_html.so","mi_http.so","mi_script.so","mi_xmlrpc.so","httpd.so","pi_http.so",
        "rabbitmq_consumer.so","statistics.so","status_report.so"
    ],
    "MEDIA RELAYS": ["mediaproxy.so","msrp_relay.so","rtpengine.so","rtpproxy.so","rtp_io.so","rtp_relay.so"],
    "EXTERNAL INTEGRATIONS": [
        "aaa_diameter.so","aaa_radius.so","freeswitch.so","freeswitch_scripting.so","h350.so","http2d.so",
        "janus.so","jsonrpc.so","launch_darkly.so","ldap.so","opentelemetry.so","prometheus.so",
        "rest_client.so","sipcapture.so","siprec.so","tracer.so","sngtc.so","snmpstats.so","stun.so","xmpp.so"
    ],
    "PROTOCOLS AND INFRASTRUCTURE": [
        "clusterer.so","tls_mgm.so","tls_openssl.so","tls_wolfssl.so","tcp_mgm.so","proto_bin.so",
        "proto_bins.so","proto_hep.so","proto_ipsec.so","proto_msrp.so","proto_sctp.so","proto_tcp.so",
        "proto_tls.so","proto_udp.so","proto_ws.so","proto_wss.so","proto_smpp.so","sockets_mgm.so"
    ],
    "OTHER": ["example.so"]
}

# Remove a previous generated catalog so reruns are idempotent.
start_marker = "#### ORAMA OPENSIPS 4.1 MODULE CATALOG - BEGIN ####"
end_marker = "#### ORAMA OPENSIPS 4.1 MODULE CATALOG - END ####"
cfg = re.sub(
    rf'(?ms)^\s*{re.escape(start_marker)}.*?^{re.escape(end_marker)}\s*\n?',
    '', cfg
)

# Re-evaluate the main route location after previous edits/catalog cleanup.
main = re.search(r'(?m)^[ \t]*route[ \t]*\{[ \t]*(?:#.*)?$', cfg)
if not main:
    raise SystemExit("Main route block not found before module catalog insertion")
insert_at = main.start()

loaded = set(re.findall(r'(?m)^[ \t]*loadmodule[ \t]+"(?:[^"]*/)?([^"/]+\.so)"', cfg))

# Detect common module paths only to report availability; comments remain harmless
# even when the server is currently OpenSIPS 4.0 and the docs catalog is 4.1/devel.
module_dirs = []
for m in re.finditer(r'(?m)^[ \t]*mpath[ \t]*=[ \t]*"([^"]+)"', cfg):
    module_dirs.append(Path(m.group(1)))
module_dirs += [
    Path('/usr/lib/x86_64-linux-gnu/opensips/modules'),
    Path('/usr/lib/opensips/modules'),
    Path('/usr/local/lib64/opensips/modules'),
    Path('/usr/local/lib/opensips/modules'),
]
seen_dirs = []
for d in module_dirs:
    if d not in seen_dirs:
        seen_dirs.append(d)
module_dirs = seen_dirs

def available(name):
    return any((d / name).is_file() for d in module_dirs)

lines = [
    start_marker,
    f"# Documentation target: OpenSIPS 4.1/devel",
    f"# Runtime detected: {runtime_version}",
    "# xlog(): CORE function in OpenSIPS 4.x; intentionally no xlog.so entry.",
    "# ACTIVE = already loaded by the real production configuration.",
    "# AVAILABLE-DISABLED = .so exists, but is not blindly loaded without required configuration.",
    "# NOT-INSTALLED = module .so not present in detected module paths.",
    "# This catalog intentionally does not expose new listeners/services by itself.",
]
for category, modules in catalog.items():
    lines.append(f"# --- {category} ---")
    for mod in modules:
        if mod in loaded:
            lines.append(f"# ACTIVE: loadmodule \"{mod}\"")
        elif available(mod):
            lines.append(f"# AVAILABLE-DISABLED: loadmodule \"{mod}\"")
        else:
            lines.append(f"# NOT-INSTALLED: loadmodule \"{mod}\"")
lines.append(end_marker)
lines.append("")

cfg = cfg[:insert_at] + "\n".join(lines) + "\n" + cfg[insert_at:]
cfg_path.write_text(cfg)
PY

if ! opensips -C -f "$CONFIG_FILE"; then
    cp -a "$LAST_BACKUP/opensips.cfg" "$CONFIG_FILE"
    if [ -f "$LAST_BACKUP/orama-security-route.cfg" ]; then
        cp -a "$LAST_BACKUP/orama-security-route.cfg" "$SECURITY_INCLUDE"
    else
        rm -f "$SECURITY_INCLUDE"
    fi
    if [ -f "$LAST_BACKUP/opensips.default" ]; then
        cp -a "$LAST_BACKUP/opensips.default" "$OPENSIPS_DEFAULTS"
    fi
    die "OpenSIPS configuration validation failed. Original OpenSIPS files restored."
fi

draw_ui "$TITLE" "Configuring 12-month instant REGISTER/Scanner bans" 78
cat > "$F2B_REGISTER_FILTER" <<'EOF'
[Definition]
failregex = ^.*ORAMA_SECURITY REGISTER_ATTACK IP=<HOST>.*$
ignoreregex =
EOF

cat > "$F2B_SCANNER_FILTER" <<'EOF'
[Definition]
failregex = ^.*ORAMA_SECURITY SCANNER_ATTACK IP=<HOST>.*$
ignoreregex =
EOF

cat > "$F2B_FLOOD_FILTER" <<'EOF'
[Definition]
failregex = ^.*ORAMA_SECURITY PIKE_FLOOD IP=<HOST>.*$
ignoreregex =
EOF

cat > "$F2B_LOCAL" <<EOF
[Definition]
dbfile = /var/lib/fail2ban/fail2ban.sqlite3
dbpurgeage = ${DB_PURGE_AGE}
EOF

IGNORE_IPS="${TRUSTED_F2B} ::1"
if [ -n "$PROVIDERS_F2B" ]; then
    IGNORE_IPS="${IGNORE_IPS} ${PROVIDERS_F2B}"
fi

cat > "$F2B_JAIL" <<EOF
[DEFAULT]
usedns = no
ignoreip = ${IGNORE_IPS}
banaction = nftables[type=multiport]
banaction_allports = nftables[type=allports]

[orama-opensips-register]
enabled = true
filter = orama-opensips-register
logpath = ${LOG_FILE}
maxretry = 1
findtime = 86400
bantime = ${BAN_12_MONTHS}
banaction = %(banaction_allports)s

[orama-opensips-scanner]
enabled = true
filter = orama-opensips-scanner
logpath = ${LOG_FILE}
maxretry = 1
findtime = 86400
bantime = ${BAN_12_MONTHS}
banaction = %(banaction_allports)s

[orama-opensips-flood]
enabled = true
filter = orama-opensips-flood
logpath = ${LOG_FILE}
maxretry = 1
findtime = 600
bantime = ${BAN_FLOOD}
banaction = %(banaction_allports)s

[sshd]
enabled = true
port = 22
maxretry = 3
findtime = 600
bantime = 86400
banaction = %(banaction_allports)s
EOF

fail2ban-client -t || die "Fail2Ban configuration validation failed."

draw_ui "$TITLE" "Restarting and verifying hardened services" 90
run_cmd systemctl restart nftables
run_cmd systemctl restart rsyslog
run_cmd systemctl enable fail2ban
run_cmd systemctl restart fail2ban
run_cmd systemctl daemon-reload
run_cmd systemctl enable opensips
systemctl reset-failed opensips >/dev/null 2>&1 || true
run_cmd systemctl restart opensips

sleep 2

systemctl is-active --quiet nftables || die "nftables is not active."
systemctl is-active --quiet fail2ban || die "fail2ban is not active."
systemctl is-active --quiet opensips || die "opensips is not active."

ss -H -lunp | grep -F "${OPENSIPS_IP}:${SIP_PORT}" | grep -q 'opensips'     || die "OpenSIPS is active but is not listening on ${OPENSIPS_IP}:${SIP_PORT}/UDP."

if [ "$SIP_PORT" -ne 5060 ] && ss -H -lunp | grep -F "${OPENSIPS_IP}:5060" | grep -q 'opensips'; then
    die "OpenSIPS is still listening on legacy ${OPENSIPS_IP}:5060."
fi

if journalctl -u opensips.service --since "-30 seconds" --no-pager 2>/dev/null | grep -Eq 'ERROR:|CRITICAL:'; then
    journalctl -u opensips.service --since "-30 seconds" --no-pager | grep -E 'ERROR:|CRITICAL:' >&2 || true
    die "OpenSIPS reported ERROR/CRITICAL messages after restart."
fi

fail2ban-client status orama-opensips-register >/dev/null 2>&1 || die "REGISTER Fail2Ban jail did not start."
nft list table inet orama_opensips >/dev/null 2>&1 || die "orama_opensips nftables table is missing."

TRUSTED_SET_STATE=$(nft list set inet orama_opensips trusted4 2>/dev/null || true)
grep -Fq "$MANAGEMENT_LAN" <<<"$TRUSTED_SET_STATE" \
    || die "Management subnet $MANAGEMENT_LAN is missing from trusted4."
if grep -Fq '10.11.100.0/22' <<<"$TRUSTED_SET_STATE"; then
    die "Firewall trust is too broad: 10.11.100.0/22 detected. Expected only $MANAGEMENT_LAN."
fi

draw_ui "$TITLE" "Security shield active and verified" 100

echo ""
echo -e "${FG_GREEN}${BOLD}Security hardening completed successfully.${RESET}"
echo "OpenSIPS IP          : $OPENSIPS_IP"
echo "Asterisk/PBX IP      : $ASTERISK_IP (FULL TRUST to OpenSIPS)"
echo "Management LAN       : $MANAGEMENT_LAN (FULL ACCESS to this OpenSIPS host)"
echo "SIP port             : $SIP_PORT"
echo "OpenSIPS listener    : ${OPENSIPS_IP}:${SIP_PORT}/UDP"
echo "OpenSIPS memory      : shared=${S_MEMORY_DEFAULT}MB private=${P_MEMORY_DEFAULT}MB"
echo "Open files/reactor   : ${OPEN_FILES_LIMIT}"
echo "SIP firewall mode    : $SIP_MODE"
echo "REGISTER ban         : 12 months / first event / all ports"
echo "Scanner ban          : 12 months / first event / all ports"
echo "PIKE flood ban       : 7 days"
echo "Fail2Ban DB retention: 400 days"
echo "Security log         : $LOG_FILE"
echo "Module catalog       : informational module inventory embedded in opensips.cfg"
echo "Module activation    : production-safe; no blind activation of DB/external/hardware modules"
echo "Backup               : $LAST_BACKUP"
echo ""
echo "Status commands:"
echo "  nft list table inet orama_opensips"
echo "  fail2ban-client status orama-opensips-register"
echo "  fail2ban-client status orama-opensips-scanner"
echo "  fail2ban-client status orama-opensips-flood"
echo "  tail -f $LOG_FILE"
echo "  ss -lunp | grep -F '${OPENSIPS_IP}:${SIP_PORT}'"
echo "  journalctl -u opensips.service --since '-2 minutes' --no-pager"
echo ""
echo "Active OpenSIPS socket:"
ss -H -lunp | grep -F "${OPENSIPS_IP}:${SIP_PORT}" || true
echo ""
echo "Active ORAMA nftables rules:"
nft list table inet orama_opensips 2>/dev/null || true
echo ""
echo "Rollback:"
echo "  bash $0 --rollback '$LAST_BACKUP'"
echo ""
if [ "$SIP_MODE" = "PUBLIC-RATELIMITED" ]; then
    echo -e "${FG_YELLOW}NOTE:${RESET} SIP/${SIP_PORT} is public with kernel rate limiting. For maximum DDoS resistance,"
    echo "      rerun with the exact provider IPv4/CIDR ranges so only the provider and LAN reach SIP."
fi

trap - EXIT
exit 0