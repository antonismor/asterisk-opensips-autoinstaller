#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive
apt-get update > /dev/null 2>&1
apt-get install -y --no-install-recommends sudo curl > /dev/null 2>&1

VERBOSE=0
if [ "$1" = "-v" ]; then
    VERBOSE=1
fi

TOTAL_STEPS=10
CURRENT_STEP=0

CREDIT_TEXT="Designed and Development By antonios.mortos@outlook.com"
BOX_WIDTH=76

# ANSI Colors
BLUE_BORDER="\033[1;34m"
WHITE_TEXT="\033[1;37m"
WHITE_BG="\033[47m"
GRAY_BG="\033[100m"
GREEN_TEXT="\033[1;32m"
RED_TEXT="\033[1;31m"
RESET="\033[0m"

print_box() {
    local title="$1"
    local percent="$2"
    local completed=$(( (percent * 40) / 100 ))
    local remaining=$(( 40 - completed ))

    local filled_bar=""
    if [ "$completed" -gt 0 ]; then
        filled_bar=$(printf "%*s" "$completed" "")
    fi

    local empty_bar=""
    if [ "$remaining" -gt 0 ]; then
        empty_bar=$(printf "%*s" "$remaining" "")
    fi

    local top_border="┌$(printf '─%.0s' $(seq 1 $((BOX_WIDTH - 2))))┐"
    local bot_border="└$(printf '─%.0s' $(seq 1 $((BOX_WIDTH - 2))))┘"
    local sep_border="├$(printf '─%.0s' $(seq 1 $((BOX_WIDTH - 2))))┤"

    local header="ASTERISK PBX & OPENSIPS AUTO INSTALLER"
    local header_pad=$(( (BOX_WIDTH - 2 - ${#header}) / 2 ))
    local header_line=$(printf "%*s%s%*s" "$header_pad" "" "$header" $(( BOX_WIDTH - 2 - header_pad - ${#header} )) "")

    local title_max_len=45
    if [ ${#title} -gt $title_max_len ]; then
        title="${title:0:$((title_max_len - 3))}..."
    fi
    local status_line=$(printf " Status: %-${title_max_len}s [%3d%%]" "$title" "$percent")
    local status_pad=$(( BOX_WIDTH - 2 - ${#status_line} ))
    status_line=$(printf "%s%*s" "$status_line" "$status_pad" "")

    local bar_pad=16
    local bar_pad_right=$(( BOX_WIDTH - 2 - bar_pad - 42 ))

    local credit_pad=$(( (BOX_WIDTH - 2 - ${#CREDIT_TEXT}) / 2 ))
    local credit_line=$(printf "%*s%s%*s" "$credit_pad" "" "$CREDIT_TEXT" $(( BOX_WIDTH - 2 - credit_pad - ${#CREDIT_TEXT} )) "")

    printf "${BLUE_BORDER}%s${RESET}\n" "$top_border"
    printf "${BLUE_BORDER}│${WHITE_TEXT}%s${BLUE_BORDER}│${RESET}\n" "$header_line"
    printf "${BLUE_BORDER}%s${RESET}\n" "$sep_border"
    printf "${BLUE_BORDER}│${RESET}%s${BLUE_BORDER}│${RESET}\n" "$status_line"
    printf "${BLUE_BORDER}│%*s[${WHITE_BG}%s${RESET}${GRAY_BG}%s${RESET}]%*s${BLUE_BORDER}│${RESET}\n" "$bar_pad" "" "$filled_bar" "$empty_bar" "$bar_pad_right" ""
    printf "${BLUE_BORDER}%s${RESET}\n" "$sep_border"
    printf "${BLUE_BORDER}│${WHITE_TEXT}%s${BLUE_BORDER}│${RESET}\n" "$credit_line"
    printf "${BLUE_BORDER}%s${RESET}\n" "$bot_border"
}

run_step() {
    local label="$1"
    shift
    CURRENT_STEP=$((CURRENT_STEP + 1))
    local percent=$(( CURRENT_STEP * 100 / TOTAL_STEPS ))

    if [ "$VERBOSE" -eq 1 ]; then
        echo "=== [Step $CURRENT_STEP/$TOTAL_STEPS] $label ==="
        "$@"
    else
        tput civis 2>/dev/null || true
        if [ "$CURRENT_STEP" -gt 1 ]; then
            printf "\033[8A"
        fi
        print_box "$label" "$percent"
        "$@" > /dev/null 2>&1
    fi
}

DEFAULT_IFACE=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -n1)
if [ -z "$DEFAULT_IFACE" ]; then
    DEFAULT_IFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -v 'lo' | head -n1)
fi

GATEWAY_IP=$(ip route | grep default | awk '{print $3}' | head -n1)
DNS_SERVER=$(grep "nameserver" /etc/resolv.conf 2>/dev/null | awk '{print $2}' | head -n1)
if [ -z "$DNS_SERVER" ]; then
    DNS_SERVER="8.8.8.8"
fi

echo "=================================================="
echo "           Network Configuration Setup            "
echo "=================================================="
read -r -p "Enter Asterisk PBX IP with CIDR (e.g. 192.168.1.100/24): " ASTERISK_IP_CIDR
read -r -p "Enter OpenSIPS Secondary IP with CIDR (e.g. 192.168.1.101/24): " OPENSIPS_IP_CIDR

IFACE="$DEFAULT_IFACE"
ASTERISK_BIND_IP=$(echo "$ASTERISK_IP_CIDR" | cut -d'/' -f1)
OPENSIPS_BIND_IP=$(echo "$OPENSIPS_IP_CIDR" | cut -d'/' -f1)

if [ -z "$ASTERISK_IP_CIDR" ] || [ -z "$OPENSIPS_IP_CIDR" ] || [ -z "$IFACE" ]; then
    echo "Error: Network parameters cannot be empty."
    exit 1
fi

cat << EOF > /etc/network/interfaces
auto lo
iface lo inet loopback

auto $IFACE
iface $IFACE inet static
    address $ASTERISK_IP_CIDR
EOF

if [ -n "$GATEWAY_IP" ]; then
    echo "    gateway $GATEWAY_IP" >> /etc/network/interfaces
fi
echo "    dns-nameservers $DNS_SERVER" >> /etc/network/interfaces

cat << EOF >> /etc/network/interfaces

auto $IFACE:1
iface $IFACE:1 inet static
    address $OPENSIPS_IP_CIDR
EOF

echo "nameserver $DNS_SERVER" > /etc/resolv.conf

systemctl restart networking >/dev/null 2>&1 || systemctl restart systemd-networkd >/dev/null 2>&1 || ifreload -a >/dev/null 2>&1 || true
ip addr flush dev "$IFACE" 2>/dev/null || true
ip addr add "$ASTERISK_IP_CIDR" dev "$IFACE" || true
ip addr add "$OPENSIPS_IP_CIDR" dev "$IFACE" label "$IFACE:1" || true
if [ -n "$GATEWAY_IP" ]; then
    ip route add default via "$GATEWAY_IP" dev "$IFACE" 2>/dev/null || true
fi

clear

if ping -c 2 -W 3 8.8.8.8 > /dev/null 2>&1 || ping -c 2 -W 3 google.com > /dev/null 2>&1; then
    printf "${GREEN_TEXT}Internet Ping - OK${RESET}\n\n"
    sleep 1.5
else
    printf "${RED_TEXT}Internet Ping - FAILED${RESET}\n\n"
    echo "Error: Cannot reach the internet. Please verify network settings."
    exit 1
fi

step_deps() {
    apt-get update
    apt-get install -y --no-install-recommends \
        build-essential \
        git \
        wget \
        subversion \
        libedit-dev \
        libsqlite3-dev \
        libjansson-dev \
        libxml2-dev \
        libssl-dev \
        libncurses5-dev \
        libnewt-dev \
        uuid-dev \
        libtool \
        automake \
        autoconf \
        pkg-config \
        bison \
        flex \
        libsrtp2-dev \
        libspandsp-dev \
        libopus-dev \
        liburiparser-dev \
        libcurl4-openssl-dev \
        libsystemd-dev \
        gettext \
        autopoint \
        tftpd-hpa
}

step_tftp() {
    mkdir -p /tftpboot
    chmod -R 777 /tftpboot
    chown -R tftp:tftp /tftpboot

    cat << 'EOF' > /etc/default/tftpd-hpa
TFTP_USERNAME="tftp"
TFTP_DIRECTORY="/tftpboot"
TFTP_ADDRESS=":69"
TFTP_OPTIONS="--secure --create"
EOF

    systemctl restart tftpd-hpa
    systemctl enable tftpd-hpa
}

step_download_asterisk() {
    cd /usr/src
    rm -rf asterisk-20* chan-sccp*
    wget https://downloads.asterisk.org/pub/telephony/asterisk/asterisk-20-current.tar.gz
    tar -zxvf asterisk-20-current.tar.gz
    cd asterisk-20.*
    contrib/scripts/get_mp3_source.sh || true
    contrib/scripts/install_prereq install-unpackaged || true
}

step_configure_asterisk() {
    cd /usr/src/asterisk-20.*
    ./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var --with-jansson --with-ssl --with-srtp --with-pjproject-bundled
    make menuselect.makeopts
    menuselect/menuselect --enable chan_pjsip menuselect.makeopts
    menuselect/menuselect --enable res_pjsip menuselect.makeopts
    menuselect/menuselect --enable res_pjsip_session menuselect.makeopts
    menuselect/menuselect --enable res_pjsip_authenticator_digest menuselect.makeopts
    menuselect/menuselect --enable res_pjsip_endpoint_identifier_ip menuselect.makeopts
    menuselect/menuselect --enable res_pjsip_endpoint_identifier_user menuselect.makeopts
    menuselect/menuselect --enable res_pjsip_registrar menuselect.makeopts
    menuselect/menuselect --enable res_pjsip_mwi menuselect.makeopts
    menuselect/menuselect --enable format_mp3 menuselect.makeopts
    menuselect/menuselect --enable codec_opus menuselect.makeopts
    menuselect/menuselect --enable codec_g722 menuselect.makeopts
    menuselect/menuselect --enable codec_resample menuselect.makeopts
    menuselect/menuselect --disable chan_sip menuselect.makeopts
}

step_compile_asterisk() {
    cd /usr/src/asterisk-20.*
    make -j$(nproc)
    make install
    make install-headers
    make samples
    make config
    ldconfig
}

step_install_sccp() {
    cd /usr/src
    rm -rf chan-sccp*
    wget https://github.com/chan-sccp/chan-sccp/archive/refs/tags/v4.3.5.tar.gz -O chan-sccp-4.3.5.tar.gz
    tar -zxvf chan-sccp-4.3.5.tar.gz
    cd chan-sccp-4.3.5

    mkdir -p tools
    if [ ! -f tools/versioncheck ]; then
        echo '#!/bin/sh' > tools/versioncheck
        echo 'echo "4.3.5"' >> tools/versioncheck
        chmod +x tools/versioncheck
    fi

    ./configure \
        --prefix=/usr \
        --with-asterisk=/usr \
        --with-asterisk-includes=/usr/include \
        --enable-conference \
        --enable-video
    make -j$(nproc)
    make install
    ldconfig
}

step_configs() {
    cat << 'EOF' > /etc/asterisk/modules.conf
[modules]
autoload=yes
preload => res_pjsip.so
preload => res_pjsip_session.so
preload => res_pjsip_authenticator_digest.so
preload => res_pjsip_registrar.so
load => chan_sccp.so
load => codec_g722.so
load => codec_opus.so
load => codec_resample.so
noload => chan_sip.so
EOF

    cat << EOF > /etc/asterisk/pjsip.conf
[global]
type=global
user_agent=Asterisk PBX

[transport-udp]
type=transport
protocol=udp
bind=${ASTERISK_BIND_IP}:5060

[endpoint-template](!)
type=endpoint
context=internal
disallow=all
allow=alaw
allow=ulaw
allow=g722
allow=opus
allow=h264
allow=vp8
allow=vp9
direct_media=no
webrtc=no

[auth-template](!)
type=auth
auth_type=userpass

[aor-template](!)
type=aor
max_contacts=3
remove_existing=yes
qualify_frequency=60

EOF

    cat << 'EOF' > /etc/asterisk/extensions.conf
[general]
static=yes
writeprotect=no
clearglobalvars=no

[globals]

[internal]
exten => _2XXX,1,NoOp(Call to ${EXTEN})
 same => n,Dial(PJSIP/${EXTEN},30)
 same => n,Hangup()
EOF

    cat << EOF > /etc/asterisk/sccp.conf
[general]
servername = Asterisk
keepalive = 60
debug = core, config
context = internal
dateformat = D.M.Y
bindaddr = ${ASTERISK_BIND_IP}
port = 2000
disallow = all
allow = alaw
allow = ulaw
allow = g722
allow = h264
firstdigittimeout = 16
digittimeout = 8
autoanswer_ring_time = 1
autoanswer_tone = 0x32
remotehangup_tone = 0x32
transfer = on
park = on
cfwdall = on
cfwdbusy = on
cfwdnoanswer = on
directed_pickup = on
directed_pickup_context = internal
dnd = on
EOF
}

step_extensions() {
    PASS='$ATdim35#1978##'

    > /root/credentials.txt
    echo "Asterisk 20 PJSIP Credentials" >> /root/credentials.txt
    echo "========================================" >> /root/credentials.txt
    echo "Asterisk IP: ${ASTERISK_BIND_IP}" >> /root/credentials.txt
    echo "OpenSIPS Secondary IP: ${OPENSIPS_BIND_IP}" >> /root/credentials.txt
    echo "Gateway: ${GATEWAY_IP}" >> /root/credentials.txt
    echo "DNS: ${DNS_SERVER}" >> /root/credentials.txt
    echo "Network Interface: ${IFACE}" >> /root/credentials.txt
    echo "TFTP Root Directory: /tftpboot" >> /root/credentials.txt
    echo "Context: internal" >> /root/credentials.txt
    echo "Audio Codecs: alaw, ulaw, g722, opus" >> /root/credentials.txt
    echo "Video Codecs: h264, vp8, vp9" >> /root/credentials.txt
    echo "Max Contacts per Extension: 3" >> /root/credentials.txt
    echo "----------------------------------------" >> /root/credentials.txt

    for ext in $(seq 2001 2051); do
cat << EOF >> /etc/asterisk/pjsip.conf
[${ext}](auth-template)
username=${ext}
password=${PASS}

[${ext}](aor-template)

[${ext}](endpoint-template)
auth=${ext}
aors=${ext}

EOF

        echo "Extension: ${ext} | Username: ${ext} | Password: ${PASS} | Max Contacts: 3" >> /root/credentials.txt
    done
}

step_services() {
    groupadd -f asterisk
    useradd -r -d /var/lib/asterisk -g asterisk asterisk 2>/dev/null || true
    
    mkdir -p /var/run/asterisk /var/log/asterisk /var/spool/asterisk /var/lib/asterisk
    chown -R asterisk:asterisk /etc/asterisk /var/run/asterisk /var/log/asterisk /var/spool/asterisk /var/lib/asterisk /usr/lib/asterisk

    systemctl daemon-reload
    systemctl enable asterisk
    systemctl restart asterisk
    sleep 2
}

step_finalize() {
    chmod 600 /root/credentials.txt
}

run_step "Updating system & build dependencies" step_deps
run_step "Configuring TFTP server" step_tftp
run_step "Downloading Asterisk 20" step_download_asterisk
run_step "Configuring Asterisk features" step_configure_asterisk
run_step "Compiling and installing Asterisk" step_compile_asterisk
run_step "Compiling and installing Chan-SCCP" step_install_sccp
run_step "Applying base configuration files" step_configs
run_step "Generating 50 PJSIP extensions" step_extensions
run_step "Enabling and starting services" step_services
run_step "Finalizing setup" step_finalize

if [ "$VERBOSE" -eq 0 ]; then
    tput cnorm 2>/dev/null || true
    printf "\n"
fi

cat /root/credentials.txt
