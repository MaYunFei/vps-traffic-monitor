#!/bin/bash

# VPS Traffic Monitor Uninstaller
# Suppport Debian, Ubuntu, CentOS, Rocky Linux, AlmaLinux

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
echo -e "${GREEN}     VPS Traffic Monitor Uninstaller           ${PLAIN}"
echo -e "${GREEN}===============================================${PLAIN}"

INSTALL_DIR="/opt/vps-traffic-monitor"
MONITOR_SCRIPT="${INSTALL_DIR}/traffic_monitor.sh"

# 1. Clean Cron Job
echo -e "\n${YELLOW}Step 1: Removing Cron Job...${PLAIN}"
if crontab -l 2>/dev/null | grep -F "$MONITOR_SCRIPT" >/dev/null; then
    crontab -l | grep -v -F "$MONITOR_SCRIPT" | crontab -
    echo -e "${GREEN}Cron job removed successfully.${PLAIN}"
else
    echo -e "No cron job found for this monitor. Skipping."
fi

# 2. Revert vnstat.conf MonthRotate to 1 (Default) if file exists
echo -e "\n${YELLOW}Step 2: Resetting vnstat billing day config...${PLAIN}"
VNSTAT_CONF="/etc/vnstat.conf"
if [ -f "$VNSTAT_CONF" ]; then
    sed -i 's/;*MonthRotate.*/MonthRotate 1/' "$VNSTAT_CONF"
    systemctl restart vnstat
    echo -e "vnstat billing day reset to default (1st)."
fi

# 3. Clean files
echo -e "\n${YELLOW}Step 3: Deleting installed files in $INSTALL_DIR...${PLAIN}"
if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
    echo -e "${GREEN}Installation directory deleted.${PLAIN}"
else
    echo -e "Installation directory does not exist. Skipping."
fi

echo -e "\n${GREEN}===============================================${PLAIN}"
echo -e "${GREEN}     Uninstall Completed successfully!          ${PLAIN}"
echo -e "${GREEN}===============================================${PLAIN}"
