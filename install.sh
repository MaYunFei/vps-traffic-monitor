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

# 1. Install dependencies (only missing ones)
echo -e "\n${YELLOW}Step 1: Checking and installing dependencies (vnstat, jq, bc, curl)...${PLAIN}"

MISSING_PKGS=""
for cmd in vnstat jq bc curl; do
    if ! command -v "$cmd" &>/dev/null; then
        MISSING_PKGS="$MISSING_PKGS $cmd"
    fi
done

if [ -z "$MISSING_PKGS" ]; then
    echo -e "${GREEN}All required dependencies are already installed.${PLAIN}"
else
    echo -e "Missing packages:${YELLOW}${MISSING_PKGS}${PLAIN}"
    case "$OS_NAME" in
        ubuntu|debian)
            apt-get update
            apt-get install -y $MISSING_PKGS
            ;;
        centos|rhel|rocky|almalinux)
            yum install -y epel-release
            yum install -y $MISSING_PKGS
            ;;
        *)
            echo -e "${RED}Unsupported OS. Please manually install: vnstat, jq, bc, curl${PLAIN}"
            exit 1
            ;;
    esac
fi

# 2. Check for existing configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/opt/vps-traffic-monitor"
CONFIG_FILE="${INSTALL_DIR}/config.env"
MONITOR_SCRIPT="${INSTALL_DIR}/traffic_monitor.sh"
EXAMPLE_CONFIG="${INSTALL_DIR}/config.env.example"

GITHUB_RAW_URL="https://raw.githubusercontent.com/MaYunFei/vps-traffic-monitor/main"

# Ensure target directory exists for deployment
mkdir -p "$INSTALL_DIR"

REBUILD_CONFIG=true
if [ -f "$CONFIG_FILE" ]; then
    echo -e "\n${YELLOW}Existing configuration detected at $CONFIG_FILE.${PLAIN}"
    read -p "Do you want to reconfigure it? [y/N]: " RECONF
    RECONF=${RECONF:-n}
    if [[ ! "$RECONF" =~ ^[Yy]$ ]]; then
        REBUILD_CONFIG=false
        echo -e "${GREEN}Using existing configuration file.${PLAIN}"
    fi
fi

# 3. Handle Script files copying or downloading
echo -e "\n${YELLOW}Step 2: Copying project files...${PLAIN}"
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

# Ensure monitor script is executable
chmod +x "$MONITOR_SCRIPT"

# 4. Interactive Configuration setup
if [ "$REBUILD_CONFIG" = "true" ]; then
    echo -e "\n${YELLOW}Step 3: Setting up configurations interactively...${PLAIN}"

    # Load existing values as defaults if configuration exists
    DEFAULT_VPS_NAME=$(hostname)
    DEFAULT_LIMIT_GB=1000
    DEFAULT_ALERT_THRESHOLD=80
    DEFAULT_RESET_DAY=1
    DEFAULT_DAILY="y"
    DEFAULT_DAILY_HOUR=21
    DEFAULT_TG_TOKEN=""
    DEFAULT_TG_CHAT=""

    if [ -f "$CONFIG_FILE" ]; then
        # Safely source config file
        source "$CONFIG_FILE" 2>/dev/null
        DEFAULT_VPS_NAME=${VPS_NAME:-$DEFAULT_VPS_NAME}
        DEFAULT_LIMIT_GB=${LIMIT_GB:-$DEFAULT_LIMIT_GB}
        DEFAULT_ALERT_THRESHOLD=${ALERT_THRESHOLD:-$DEFAULT_ALERT_THRESHOLD}
        DEFAULT_DAILY_HOUR=${DAILY_REPORT_HOUR:-$DEFAULT_DAILY_HOUR}
        DEFAULT_TG_TOKEN=$TELEGRAM_BOT_TOKEN
        DEFAULT_TG_CHAT=$TELEGRAM_CHAT_ID
        if [ "$DAILY_REPORT" = "false" ]; then
            DEFAULT_DAILY="n"
        fi

        # Try to read MonthRotate directly from /etc/vnstat.conf
        VNSTAT_CONF="/etc/vnstat.conf"
        if [ -f "$VNSTAT_CONF" ]; then
            VNSTAT_RESET_DAY=$(grep -E "^MonthRotate" "$VNSTAT_CONF" | head -n 1 | awk '{print $2}')
            DEFAULT_RESET_DAY=${VNSTAT_RESET_DAY:-$DEFAULT_RESET_DAY}
        fi
    fi

    # Custom Hostname
    echo -e "\n${BLUE}[1/5] 主机识别名称 (VPS_NAME)${PLAIN}"
    echo -e "说明: 用于区分多台服务器，将在 Telegram 告警卡片标题中显示。"
    read -p "请输入此 VPS 的展示名称 [默认: $DEFAULT_VPS_NAME]: " VPS_NAME
    VPS_NAME=${VPS_NAME:-$DEFAULT_VPS_NAME}

    # Limit GB
    echo -e "\n${BLUE}[2/5] 月度流量限制总额 (LIMIT_GB)${PLAIN}"
    echo -e "说明: VPS 商家提供的月度总流量限制数 (单位: GB)。"
    read -p "请输入限制额度 [默认: $DEFAULT_LIMIT_GB]: " LIMIT_GB
    LIMIT_GB=${LIMIT_GB:-$DEFAULT_LIMIT_GB}
    if ! [[ "$LIMIT_GB" =~ ^[0-9]+$ ]]; then
        LIMIT_GB=$DEFAULT_LIMIT_GB
    fi

    # Alert Threshold
    echo -e "\n${BLUE}[3/5] 起始报警阈值比例 (ALERT_THRESHOLD)${PLAIN}"
    echo -e "说明: 流量消耗达到此百分比时开始报警，超量后还会阶梯式在 90%、95%、100% 时各告警一次。"
    read -p "请输入起始警报比例 (0-100) [默认: $DEFAULT_ALERT_THRESHOLD]: " ALERT_THRESHOLD
    ALERT_THRESHOLD=${ALERT_THRESHOLD:-$DEFAULT_ALERT_THRESHOLD}
    if ! [[ "$ALERT_THRESHOLD" =~ ^[0-9]+$ ]] || [ "$ALERT_THRESHOLD" -lt 0 ] || [ "$ALERT_THRESHOLD" -gt 100 ]; then
        ALERT_THRESHOLD=$DEFAULT_ALERT_THRESHOLD
    fi

    # Reset Day
    echo -e "\n${BLUE}[4/5] 账单重置日期 (RESET_DAY)${PLAIN}"
    echo -e "说明: 你的 VPS 账单流量重置日(如 ZgoCloud 为每月 22 号)。"
    echo -e "⚠️  受 vnstat 底层月份天数兼容设计限制，只能设置为 1-28 号。"
    read -p "请输入每月重置日期 (1-28) [默认: $DEFAULT_RESET_DAY]: " RESET_DAY
    RESET_DAY=${RESET_DAY:-$DEFAULT_RESET_DAY}
    if ! [[ "$RESET_DAY" =~ ^[0-9]+$ ]] || [ "$RESET_DAY" -lt 1 ] || [ "$RESET_DAY" -gt 28 ]; then
        echo -e "${RED}输入无效，默认回退到 $DEFAULT_RESET_DAY 号。${PLAIN}"
        RESET_DAY=$DEFAULT_RESET_DAY
    fi

    # Daily Report Setting
    echo -e "\n${BLUE}[5/5] 每日例行流量总结报告 (DAILY_REPORT)${PLAIN}"
    echo -e "说明: 每天定时向你汇报当前已用/剩余流量总结。"
    read -p "是否开启运行报告? (y/n) [默认: $DEFAULT_DAILY]: " WANT_DAILY
    WANT_DAILY=${WANT_DAILY:-$DEFAULT_DAILY}
    if [[ "$WANT_DAILY" =~ ^[Nn]$ ]]; then
        DAILY_REPORT=false
        DAILY_REPORT_HOUR=9
    else
        DAILY_REPORT=true
        read -p "   请输入每天定时推送的时间 (整点小时 0-23) [默认: $DEFAULT_DAILY_HOUR]: " DAILY_HOUR
        DAILY_REPORT_HOUR=${DAILY_HOUR:-$DEFAULT_DAILY_HOUR}
        if ! [[ "$DAILY_REPORT_HOUR" =~ ^[0-9]+$ ]] || [ "$DAILY_REPORT_HOUR" -lt 0 ] || [ "$DAILY_REPORT_HOUR" -gt 23 ]; then
            DAILY_REPORT_HOUR=$DEFAULT_DAILY_HOUR
        fi
    fi

    # Telegram Credentials
    echo -e "\n${YELLOW}Please specify Telegram Bot configurations:${PLAIN}"
    if [ -n "$DEFAULT_TG_TOKEN" ]; then
        read -p "Telegram Bot Token [默认: $DEFAULT_TG_TOKEN]: " TG_TOKEN
        TG_TOKEN=${TG_TOKEN:-$DEFAULT_TG_TOKEN}
    else
        read -p "Telegram Bot Token: " TG_TOKEN
    fi

    if [ -n "$DEFAULT_TG_CHAT" ]; then
        read -p "Telegram Chat ID [默认: $DEFAULT_TG_CHAT]: " TG_CHAT
        TG_CHAT=${TG_CHAT:-$DEFAULT_TG_CHAT}
    else
        read -p "Telegram Chat ID: " TG_CHAT
    fi

    # Print a nice summary during configuration writing
    cat <<EOF > "$CONFIG_FILE"
# Telegram Bot Token
TELEGRAM_BOT_TOKEN="${TG_TOKEN}"

# Telegram Chat ID or Group ID
TELEGRAM_CHAT_ID="${TG_CHAT}"

# VPS Total monthly traffic limit in GB
LIMIT_GB=${LIMIT_GB}

# Network interface to monitor. If left empty, the script will auto-detect the default interface.
INTERFACE=""

# Warning threshold percentage (e.g., alert when usage reaches 80%)
ALERT_THRESHOLD=${ALERT_THRESHOLD}

# State directory for saving alert levels to prevent spam
STATE_DIR="/tmp"

# Enable daily traffic report summary (true/false)
DAILY_REPORT=${DAILY_REPORT}

# The hour of the day (0-23) to send the daily report summary (e.g., 9 for 9:00 AM)
DAILY_REPORT_HOUR=${DAILY_REPORT_HOUR}

# Optionally set a custom hostname to identify which VPS is reporting
VPS_NAME="${VPS_NAME}"
EOF

    # Config vnstat billing reset day
    VNSTAT_CONF="/etc/vnstat.conf"
    if [ -f "$VNSTAT_CONF" ]; then
        # Modify MonthRotate line in vnstat.conf
        # Remove all existing MonthRotate lines (commented or not), then append the new one
        sed -i '/MonthRotate/d' "$VNSTAT_CONF"
        echo "MonthRotate $RESET_DAY" >> "$VNSTAT_CONF"
        # Restart vnstat service
        systemctl restart vnstat
        systemctl enable vnstat
    fi
else
    # Config is kept, we parse values to display the summary
    # Load config variables to print summary
    source "$CONFIG_FILE"
    RESET_DAY=$(grep -E "^MonthRotate" /etc/vnstat.conf | head -n 1 | awk '{print $2}')
    RESET_DAY=${RESET_DAY:-1}
    TG_TOKEN=$TELEGRAM_BOT_TOKEN
    TG_CHAT=$TELEGRAM_CHAT_ID
fi

# 5. Setup Cron Job
echo -e "\n${YELLOW}Step 4: Setting up Cron Job (Every 5 Minutes)...${PLAIN}"
CRON_CMD="*/5 * * * * /bin/bash $MONITOR_SCRIPT > /dev/null 2>&1"

# Check if cron job already exists to avoid duplicates
(crontab -l 2>/dev/null | grep -F "$MONITOR_SCRIPT" >/dev/null)
if [ $? -eq 0 ]; then
    echo -e "Cron job already exists. Skipping."
else
    (crontab -l 2>/dev/null; echo "$CRON_CMD") | crontab -
    echo -e "Cron job scheduled: ${GREEN}Every 5 Minutes${PLAIN}"
fi

# Show structural summary report
echo -e "\n${GREEN}===============================================${PLAIN}"
echo -e "${GREEN}     Installation Complete successfully!       ${PLAIN}"
echo -e "${GREEN}===============================================${PLAIN}"
echo -e "\n${BLUE}=== VPS Traffic Monitor Configurations ===${PLAIN}"
echo -e "• VPS ID/Name:   ${YELLOW}${VPS_NAME}${PLAIN}"
echo -e "• Traffic Limit: ${YELLOW}${LIMIT_GB} GB${PLAIN}"
echo -e "• Alert Threshold:  ${YELLOW}${ALERT_THRESHOLD}%${PLAIN}"
echo -e "• Billing Reset: Monthly Day ${YELLOW}${RESET_DAY}${PLAIN} (via vnstat)"
echo -e "• Daily Report:  ${YELLOW}${DAILY_REPORT}${PLAIN}"
if [ "$DAILY_REPORT" = "true" ]; then
    echo -e "  └─ Report Hour: ${YELLOW}${DAILY_REPORT_HOUR}:00${PLAIN}"
fi
echo -e "• TG Token:      ${YELLOW}${TG_TOKEN:-(Not Configured)}${PLAIN}"
echo -e "• TG Chat ID:    ${YELLOW}${TG_CHAT:-(Not Configured)}${PLAIN}"
echo -e "• Absolute Path: ${YELLOW}${INSTALL_DIR}${PLAIN}"
echo -e "==========================================="

# Automatically trigger channel test if credentials are supplied
if [ -n "$TG_TOKEN" ] && [ -n "$TG_CHAT" ]; then
    echo -e "\n${YELLOW}正在向你的 Telegram 发送真实数据测试消息...${PLAIN}"
    /bin/bash "$MONITOR_SCRIPT" test
    echo -e "\n📢 ${GREEN}请立刻检查你的 Telegram 客户端以确认已经收到测试消息！${PLAIN}"
    echo -e "💡 并温馨提示：如果你没有在手机上收到任何消息，说明很有可能你刚才输入的"
    echo -e "   ${RED}Telegram Bot Token${PLAIN} 或者是 ${RED}Chat ID${PLAIN} 填写有误，请查验后重新运行安装脚本进行修改。"
fi

echo -e "\n💡 ${YELLOW}任何时候都可以手动触发一次测试推送：${PLAIN}"
echo -e "   ${GREEN}${MONITOR_SCRIPT} test${PLAIN}"
