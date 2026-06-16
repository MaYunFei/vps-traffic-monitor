#!/bin/bash

# VPS Traffic Monitor Uninstaller
# Support Debian, Ubuntu, CentOS, Rocky Linux, AlmaLinux

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

# Check if run as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root. / 错误: 此脚本必须以 root 权限运行。${PLAIN}" >&2
    exit 1
fi

INSTALL_DIR="/opt/vps-traffic-monitor"
CONFIG_FILE="${INSTALL_DIR}/config.env"
MONITOR_SCRIPT="${INSTALL_DIR}/traffic_monitor.sh"

# Detect configured language, fallback to English
MONITOR_LANG="en"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE" 2>/dev/null
fi

echo -e "${GREEN}===============================================${PLAIN}"
if [ "$MONITOR_LANG" = "zh" ]; then
    echo -e "${GREEN}     VPS 流量监控卸载器                       ${PLAIN}"
else
    echo -e "${GREEN}     VPS Traffic Monitor Uninstaller           ${PLAIN}"
fi
echo -e "${GREEN}===============================================${PLAIN}"

# 1. Clean Cron Job
if [ "$MONITOR_LANG" = "zh" ]; then
    echo -e "\n${YELLOW}步骤 1: 正在移除 Cron 定时任务...${PLAIN}"
else
    echo -e "\n${YELLOW}Step 1: Removing Cron Job...${PLAIN}"
fi

if crontab -l 2>/dev/null | grep -F "$MONITOR_SCRIPT" >/dev/null; then
    crontab -l | grep -v -F "$MONITOR_SCRIPT" | crontab -
    if [ "$MONITOR_LANG" = "zh" ]; then
        echo -e "${GREEN}Cron 定时任务已成功移除。${PLAIN}"
    else
        echo -e "${GREEN}Cron job removed successfully.${PLAIN}"
    fi
else
    if [ "$MONITOR_LANG" = "zh" ]; then
        echo -e "未发现关联本监控的定时任务，自动跳过。"
    else
        echo -e "No cron job found for this monitor. Skipping."
    fi
fi

# 2. Clean systemd active command listener service
if [ "$MONITOR_LANG" = "zh" ]; then
    echo -e "\n${YELLOW}步骤 2: 正在关闭并清理后台 Telegram 监听服务 (vps-traffic-listener)...${PLAIN}"
else
    echo -e "\n${YELLOW}Step 2: Stopping and removing Telegram listener daemon (vps-traffic-listener)...${PLAIN}"
fi

LISTENER_SERVICE_FILE="/etc/systemd/system/vps-traffic-listener.service"
if [ -f "$LISTENER_SERVICE_FILE" ] || systemctl list-unit-files | grep -q "vps-traffic-listener.service" 2>/dev/null; then
    systemctl stop vps-traffic-listener.service 2>/dev/null
    systemctl disable vps-traffic-listener.service 2>/dev/null
    rm -f "$LISTENER_SERVICE_FILE"
    systemctl daemon-reload 2>/dev/null
    if [ "$MONITOR_LANG" = "zh" ]; then
        echo -e "${GREEN}后台监听服务已成功停用并删除。${PLAIN}"
    else
        echo -e "${GREEN}Listener daemon stopped and service file deleted.${PLAIN}"
    fi
else
    if [ "$MONITOR_LANG" = "zh" ]; then
        echo -e "未检查到已启用的后台监听服务，自动跳过。"
    else
        echo -e "No background listener service detected. Skipping."
    fi
fi

# 3. Revert vnstat.conf MonthRotate to 1 (Default) if file exists
if [ "$MONITOR_LANG" = "zh" ]; then
    echo -e "\n${YELLOW}步骤 3: 正在恢复 vnstat 个性化账单重置周期设置...${PLAIN}"
else
    echo -e "\n${YELLOW}Step 3: Resetting vnstat billing day config...${PLAIN}"
fi

VNSTAT_CONF="/etc/vnstat.conf"
if [ -f "$VNSTAT_CONF" ]; then
    sed -i 's/;*MonthRotate.*/MonthRotate 1/' "$VNSTAT_CONF"
    systemctl restart vnstat 2>/dev/null
    if [ "$MONITOR_LANG" = "zh" ]; then
        echo -e "vnstat 账单重置日已重置为默认值 (每月 1 号)。"
    else
        echo -e "vnstat billing day reset to default (1st)."
    fi
fi

# 4. Clean physical files
if [ "$MONITOR_LANG" = "zh" ]; then
    echo -e "\n${YELLOW}步骤 4: 正在彻底删除绝对路径安装目录 $INSTALL_DIR...${PLAIN}"
else
    echo -e "\n${YELLOW}Step 4: Deleting installed files in $INSTALL_DIR...${PLAIN}"
fi

if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
    if [ "$MONITOR_LANG" = "zh" ]; then
        echo -e "${GREEN}安装物理路径彻底清除完成。${PLAIN}"
    else
        echo -e "${GREEN}Installation directory deleted.${PLAIN}"
    fi
else
    if [ "$MONITOR_LANG" = "zh" ]; then
        echo -e "未检测到物理安装目录，自动跳过。"
    else
        echo -e "Installation directory does not exist. Skipping."
    fi
fi

echo -e "\n${GREEN}===============================================${PLAIN}"
if [ "$MONITOR_LANG" = "zh" ]; then
    echo -e "${GREEN}           流量监测程序成功卸载完成！            ${PLAIN}"
else
    echo -e "${GREEN}     Uninstall Completed successfully!          ${PLAIN}"
fi
echo -e "${GREEN}===============================================${PLAIN}"
