#!/bin/bash

# VPS Traffic Monitor Automatic Installer
# Support Debian, Ubuntu, CentOS, Rocky Linux, AlmaLinux

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

# Check if run as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root.${PLAIN}" >&2
    exit 1
fi

echo -e "${GREEN}===============================================${PLAIN}"
echo -e "${GREEN}     VPS Traffic Monitor Installer             ${PLAIN}"
echo -e "${GREEN}===============================================${PLAIN}"

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_NAME=$ID
elif [ -f /etc/redhat-release ]; then
    OS_NAME="rhel"
else
    OS_NAME="unknown"
fi

echo -e "OS Detected: ${YELLOW}$OS_NAME${PLAIN}"

# 1. Install dependencies
echo -e "\n${YELLOW}Step 1: Installing dependencies (vnstat, jq, bc, curl)...${PLAIN}"
case "$OS_NAME" in
    ubuntu|debian)
        apt-get update
        apt-get install -y vnstat jq bc curl
        ;;
    centos|rhel|rocky|almalinux)
        # Enable EPEL first for vnstat
        yum install -y epel-release
        yum install -y vnstat jq bc curl
        ;;
    *)
        echo -e "${RED}Unsupported OS. Please manually install: vnstat, jq, bc, curl${PLAIN}"
        exit 1
        ;;
esac

# 2. Config vnstat billing reset day
echo -e "\n${YELLOW}Step 2: Configuring vnstat MonthRotate day...${PLAIN}"
read -p "Enter your monthly billing billing cycle reset day (1-28) [default: 22]: " RESET_DAY
RESET_DAY=${RESET_DAY:-22}

if ! [[ "$RESET_DAY" =~ ^[0-9]+$ ]] || [ "$RESET_DAY" -lt 1 ] || [ "$RESET_DAY" -gt 28 ]; then
    echo -e "${RED}Invalid day, falling back to 22.${PLAIN}"
    RESET_DAY=22
fi

VNSTAT_CONF="/etc/vnstat.conf"
if [ -f "$VNSTAT_CONF" ]; then
    # Modify MonthRotate line in vnstat.conf
    # Typically looks like: MonthRotate 1
    sed -i 's/;*MonthRotate.*/MonthRotate '$RESET_DAY'/' "$VNSTAT_CONF"
    echo -e "vnstat billing cycle set to reset on day: ${GREEN}$RESET_DAY${PLAIN}"

    # Restart vnstat service
    systemctl restart vnstat
    systemctl enable vnstat
    echo -e "vnstat service restarted."
else
    echo -e "${RED}Warning: vnstat.conf not found at $VNSTAT_CONF. Please configure manually.${PLAIN}"
fi

# 3. Setup Config File and Scripts
echo -e "\n${YELLOW}Step 3: Setting up local configurations and scripts...${PLAIN}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/opt/vps-traffic-monitor"

# Ensure target directory exists
mkdir -p "$INSTALL_DIR"
CONFIG_FILE="${INSTALL_DIR}/config.env"
MONITOR_SCRIPT="${INSTALL_DIR}/traffic_monitor.sh"
EXAMPLE_CONFIG="${INSTALL_DIR}/config.env.example"

GITHUB_RAW_URL="https://raw.githubusercontent.com/MaYunFei/vps-traffic-monitor/main"

# Copy local files if in a cloned repository, otherwise download them
if [ -f "${SCRIPT_DIR}/traffic_monitor.sh" ]; then
    cp "${SCRIPT_DIR}/traffic_monitor.sh" "$MONITOR_SCRIPT"
    echo -e "Copied traffic_monitor.sh to ${GREEN}${INSTALL_DIR}${PLAIN}"
else
    echo -e "Downloading ${YELLOW}traffic_monitor.sh${PLAIN} from repository..."
    curl -fsSL "${GITHUB_RAW_URL}/traffic_monitor.sh" -o "$MONITOR_SCRIPT"
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Failed to download traffic_monitor.sh${PLAIN}" >&2
        exit 1
    fi
fi

if [ -f "${SCRIPT_DIR}/config.env.example" ]; then
    cp "${SCRIPT_DIR}/config.env.example" "$EXAMPLE_CONFIG"
    echo -e "Copied config.env.example to ${GREEN}${INSTALL_DIR}${PLAIN}"
else
    echo -e "Downloading ${YELLOW}config.env.example${PLAIN} from repository..."
    curl -fsSL "${GITHUB_RAW_URL}/config.env.example" -o "$EXAMPLE_CONFIG"
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Failed to download config.env.example${PLAIN}" >&2
        exit 1
    fi
fi

if [ ! -f "$CONFIG_FILE" ]; then
    cp "$EXAMPLE_CONFIG" "$CONFIG_FILE"
    echo -e "Created ${GREEN}config.env${PLAIN} from example."
else
    echo -e "${GREEN}config.env${PLAIN} already exists. Skipping copy."
fi

# Provide instructions for TG setup
echo -e "\n${YELLOW}Please specify Telegram Bot configurations:${PLAIN}"
read -p "Telegram Bot Token: " TG_TOKEN
read -p "Telegram Chat ID: " TG_CHAT

if [ -n "$TG_TOKEN" ] && [ -n "$TG_CHAT" ]; then
    sed -i 's/TELEGRAM_BOT_TOKEN=".*"/TELEGRAM_BOT_TOKEN="'$TG_TOKEN'"/' "$CONFIG_FILE"
    sed -i 's/TELEGRAM_CHAT_ID=".*"/TELEGRAM_CHAT_ID="'$TG_CHAT'"/' "$CONFIG_FILE"
    echo -e "Telegram settings updated in ${GREEN}config.env${PLAIN}."
else
    echo -e "${YELLOW}Credentials left empty. Please update config.env manually before running.${PLAIN}"
fi

# Ensure executable permissions
chmod +x "$MONITOR_SCRIPT"

# 4. Setup Cron Job
echo -e "\n${YELLOW}Step 4: Setting up Cron Job (Every 5 Minutes)...${PLAIN}"
CRON_CMD="*/5 * * * * /bin/bash $MONITOR_SCRIPT > /dev/null 2>&1"

# Check if cron job already exists to avoid duplicates
(crontab -l 2>/dev/null | grep -F "$MONITOR_SCRIPT" >/dev/null)
if [ $? -eq 0 ]; then
    echo -e "Cron job already exists. Skipping."
else
    (crontab -l 2>/dev/null; echo "$CRON_CMD") | crontab -
    echo -e "Cron job scheduled: ${GREEN}Hourly${PLAIN}"
fi

echo -e "\n${GREEN}===============================================${PLAIN}"
echo -e "${GREEN}     Installation Complete successfully!       ${PLAIN}"
echo -e "${GREEN}===============================================${PLAIN}"
echo -e "Make sure you completed configuration in: ${YELLOW}${CONFIG_FILE}${PLAIN}"

# Automatically trigger channel test if credentials are supplied
if [ -n "$TG_TOKEN" ] && [ -n "$TG_CHAT" ]; then
    echo -e "\n${YELLOW}Triggering Telegram notification test...${PLAIN}"
    /bin/bash "$MONITOR_SCRIPT" test
else
    echo -e "You can run it manually to test: ${YELLOW}${MONITOR_SCRIPT} test${PLAIN}"
fi
