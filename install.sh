#!/bin/bash

# VPS Traffic Monitor Automatic Installer
# Support Debian, Ubuntu, CentOS, Rocky Linux, AlmaLinux

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PLAIN='\033[0m'

# Check if run as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root. / 错误: 此脚本必须以 root 权限运行。${PLAIN}" >&2
    exit 1
fi

echo -e "${GREEN}===============================================${PLAIN}"
echo -e "${GREEN}     VPS Traffic Monitor Installer             ${PLAIN}"
echo -e "${GREEN}===============================================${PLAIN}"

# Choose language
echo -e "Please select your language / 请选择安装语言:"
echo -e "1. English (Default)"
echo -e "2. 简体中文"
read -p "Select [1-2]: " LANG_SEL
LANG_SEL=${LANG_SEL:-1}

if [ "$LANG_SEL" -eq 2 ]; then
    MONITOR_LANG="zh"
else
    MONITOR_LANG="en"
fi

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_NAME=$ID
elif [ -f /etc/redhat-release ]; then
    OS_NAME="rhel"
else
    OS_NAME="unknown"
fi

if [ "$MONITOR_LANG" = "zh" ]; then
    echo -e "检测到系统操作系统: ${YELLOW}$OS_NAME${PLAIN}"
    echo -e "\n${YELLOW}步骤 1: 检查并安装缺失依赖 (vnstat, jq, bc, curl, systemd)...${PLAIN}"
else
    echo -e "OS Detected: ${YELLOW}$OS_NAME${PLAIN}"
    echo -e "\n${YELLOW}Step 1: Checking and installing dependencies (vnstat, jq, bc, curl, systemd)...${PLAIN}"
fi

MISSING_PKGS=""
for cmd in vnstat jq bc curl; do
    if ! command -v "$cmd" &>/dev/null; then
        MISSING_PKGS="$MISSING_PKGS $cmd"
    fi
done

if [ -z "$MISSING_PKGS" ]; then
    if [ "$MONITOR_LANG" = "zh" ]; then
        echo -e "${GREEN}所有必要的依赖项都已安装。${PLAIN}"
    else
        echo -e "${GREEN}All required dependencies are already installed.${PLAIN}"
    fi
else
    if [ "$MONITOR_LANG" = "zh" ]; then
        echo -e "缺失的软件包:${YELLOW}${MISSING_PKGS}${PLAIN}"
    else
        echo -e "Missing packages:${YELLOW}${MISSING_PKGS}${PLAIN}"
    fi
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
            if [ "$MONITOR_LANG" = "zh" ]; then
                echo -e "${RED}不支持的系统。请手动安装: vnstat, jq, bc, curl${PLAIN}"
            else
                echo -e "${RED}Unsupported OS. Please manually install: vnstat, jq, bc, curl${PLAIN}"
            fi
            exit 1
            ;;
    esac
fi

# Ensure vnstat is started and enabled
systemctl enable vnstat 2>/dev/null
systemctl start vnstat 2>/dev/null

# 2. Check for existing configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/opt/vps-traffic-monitor"
CONFIG_FILE="${INSTALL_DIR}/config.env"
MONITOR_SCRIPT="${INSTALL_DIR}/traffic_monitor.sh"
LISTENER_SCRIPT="${INSTALL_DIR}/traffic_bot_listener.sh"
UNINSTALL_SCRIPT="${INSTALL_DIR}/uninstall.sh"
EXAMPLE_CONFIG="${INSTALL_DIR}/config.env.example"

GITHUB_RAW_URL="https://raw.githubusercontent.com/MaYunFei/vps-traffic-monitor/main"

# Ensure target directory exists for deployment
mkdir -p "$INSTALL_DIR"

REBUILD_CONFIG=true
if [ -f "$CONFIG_FILE" ]; then
    if [ "$MONITOR_LANG" = "zh" ]; then
        echo -e "\n${YELLOW}在 $CONFIG_FILE 检测到已有配置。${PLAIN}"
        read -p "是否要重新配置？ [y/N]: " RECONF
    else
        echo -e "\n${YELLOW}Existing configuration detected at $CONFIG_FILE.${PLAIN}"
        read -p "Do you want to reconfigure it? [y/N]: " RECONF
    fi
    RECONF=${RECONF:-n}
    if [[ ! "$RECONF" =~ ^[Yy]$ ]]; then
        REBUILD_CONFIG=false
        if [ "$MONITOR_LANG" = "zh" ]; then
            echo -e "${GREEN}使用已有配置文件。${PLAIN}"
        else
            echo -e "${GREEN}Using existing configuration file.${PLAIN}"
        fi
    fi
fi

# 3. Handle Script files copying or downloading
if [ "$MONITOR_LANG" = "zh" ]; then
    echo -e "\n${YELLOW}步骤 2: 正在复制项目文件...${PLAIN}"
else
    echo -e "\n${YELLOW}Step 2: Copying project files...${PLAIN}"
fi

# Copy or download traffic_monitor.sh
if [ -f "${SCRIPT_DIR}/traffic_monitor.sh" ]; then
    cp "${SCRIPT_DIR}/traffic_monitor.sh" "$MONITOR_SCRIPT"
    if [ "$MONITOR_LANG" = "zh" ]; then
        echo -e "已复制 traffic_monitor.sh 到 ${GREEN}${INSTALL_DIR}${PLAIN}"
    else
        echo -e "Copied traffic_monitor.sh to ${GREEN}${INSTALL_DIR}${PLAIN}"
    fi
else
    if [ "$MONITOR_LANG" = "zh" ]; then
        echo -e "正在从仓库下载 ${YELLOW}traffic_monitor.sh${PLAIN}..."
    else
        echo -e "Downloading ${YELLOW}traffic_monitor.sh${PLAIN} from repository..."
    fi
    curl -fsSL "${GITHUB_RAW_URL}/traffic_monitor.sh" -o "$MONITOR_SCRIPT"
    if [ $? -ne 0 ]; then
        if [ "$MONITOR_LANG" = "zh" ]; then
            echo -e "${RED}错误: 无法下载 traffic_monitor.sh${PLAIN}" >&2
        else
            echo -e "${RED}Error: Failed to download traffic_monitor.sh${PLAIN}" >&2
        fi
        exit 1
    fi
fi

# Copy or download traffic_bot_listener.sh
if [ -f "${SCRIPT_DIR}/traffic_bot_listener.sh" ]; then
    cp "${SCRIPT_DIR}/traffic_bot_listener.sh" "$LISTENER_SCRIPT"
    if [ "$MONITOR_LANG" = "zh" ]; then
        echo -e "已复制 traffic_bot_listener.sh 到 ${GREEN}${INSTALL_DIR}${PLAIN}"
    else
        echo -e "Copied traffic_bot_listener.sh to ${GREEN}${INSTALL_DIR}${PLAIN}"
    fi
else
    if [ "$MONITOR_LANG" = "zh" ]; then
        echo -e "正在从仓库下载 ${YELLOW}traffic_bot_listener.sh${PLAIN}..."
    else
        echo -e "Downloading ${YELLOW}traffic_bot_listener.sh${PLAIN} from repository..."
    fi
    curl -fsSL "${GITHUB_RAW_URL}/traffic_bot_listener.sh" -o "$LISTENER_SCRIPT"
    if [ $? -ne 0 ]; then
        if [ "$MONITOR_LANG" = "zh" ]; then
            echo -e "${RED}错误: 无法下载 traffic_bot_listener.sh${PLAIN}" >&2
        else
            echo -e "${RED}Error: Failed to download traffic_bot_listener.sh${PLAIN}" >&2
        fi
        exit 1
    fi
fi

# Copy or download config.env.example
if [ -f "${SCRIPT_DIR}/config.env.example" ]; then
    cp "${SCRIPT_DIR}/config.env.example" "$EXAMPLE_CONFIG"
    if [ "$MONITOR_LANG" = "zh" ]; then
        echo -e "已复制 config.env.example 到 ${GREEN}${INSTALL_DIR}${PLAIN}"
    else
        echo -e "Copied config.env.example to ${GREEN}${INSTALL_DIR}${PLAIN}"
    fi
else
    if [ "$MONITOR_LANG" = "zh" ]; then
        echo -e "正在从仓库下载 ${YELLOW}config.env.example${PLAIN}..."
    else
        echo -e "Downloading ${YELLOW}config.env.example${PLAIN} from repository..."
    fi
    curl -fsSL "${GITHUB_RAW_URL}/config.env.example" -o "$EXAMPLE_CONFIG"
    if [ $? -ne 0 ]; then
        if [ "$MONITOR_LANG" = "zh" ]; then
            echo -e "${RED}错误: 无法下载 config.env.example${PLAIN}" >&2
        else
            echo -e "${RED}Error: Failed to download config.env.example${PLAIN}" >&2
        fi
        exit 1
    fi
fi

# Copy or download uninstall.sh
if [ -f "${SCRIPT_DIR}/uninstall.sh" ]; then
    cp "${SCRIPT_DIR}/uninstall.sh" "$UNINSTALL_SCRIPT"
    if [ "$MONITOR_LANG" = "zh" ]; then
        echo -e "已复制 uninstall.sh 到 ${GREEN}${INSTALL_DIR}${PLAIN}"
    else
        echo -e "Copied uninstall.sh to ${GREEN}${INSTALL_DIR}${PLAIN}"
    fi
else
    if [ "$MONITOR_LANG" = "zh" ]; then
        echo -e "正在从仓库下载 ${YELLOW}uninstall.sh${PLAIN}..."
    else
        echo -e "Downloading ${YELLOW}uninstall.sh${PLAIN} from repository..."
    fi
    curl -fsSL "${GITHUB_RAW_URL}/uninstall.sh" -o "$UNINSTALL_SCRIPT"
    if [ $? -ne 0 ]; then
        if [ "$MONITOR_LANG" = "zh" ]; then
            echo -e "${RED}错误: 无法下载 uninstall.sh${PLAIN}" >&2
        else
            echo -e "${RED}Error: Failed to download uninstall.sh${PLAIN}" >&2
        fi
        exit 1
    fi
fi

# Ensure scripts are executable
chmod +x "$MONITOR_SCRIPT"
chmod +x "$LISTENER_SCRIPT"
chmod +x "$UNINSTALL_SCRIPT"

# 4. Interactive Configuration setup
if [ "$REBUILD_CONFIG" = "true" ]; then
    if [ "$MONITOR_LANG" = "zh" ]; then
        echo -e "\n${YELLOW}步骤 3: 正在交互式配置参数...${PLAIN}"
    else
        echo -e "\n${YELLOW}Step 3: Setting up configurations interactively...${PLAIN}"
    fi

    # Load existing values as defaults if configuration exists
    DEFAULT_VPS_NAME=$(hostname)
    DEFAULT_LIMIT_GB=1000
    DEFAULT_INITIAL_USED=0
    DEFAULT_ALERT_THRESHOLD=80
    DEFAULT_RESET_DAY=1
    DEFAULT_DAILY="y"
    DEFAULT_DAILY_HOUR=21
    DEFAULT_TG_TOKEN=""
    DEFAULT_TG_CHAT=""
    DEFAULT_ENABLE_LISTENER="n"

    if [ -f "$CONFIG_FILE" ]; then
        # Safely source config file
        source "$CONFIG_FILE" 2>/dev/null
        DEFAULT_VPS_NAME=${VPS_NAME:-$DEFAULT_VPS_NAME}
        DEFAULT_LIMIT_GB=${LIMIT_GB:-$DEFAULT_LIMIT_GB}
        DEFAULT_INITIAL_USED=${INITIAL_USED_GB:-$DEFAULT_INITIAL_USED}
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

    # Check if listener service is currently active/enabled to set default prompt
    if systemctl is-active vps-traffic-listener.service &>/dev/null || systemctl is-enabled vps-traffic-listener.service &>/dev/null; then
        DEFAULT_ENABLE_LISTENER="y"
    fi

    # Custom Hostname
    if [ "$MONITOR_LANG" = "zh" ]; then
        echo -e "\n${BLUE}[1/6] 主机识别名称 (VPS_NAME)${PLAIN}"
        echo -e "说明: 用于区分多台服务器，将在 Telegram 告警卡片标题中显示。"
        read -p "请输入此 VPS 的展示名称 [默认: $DEFAULT_VPS_NAME]: " VPS_NAME
    else
        echo -e "\n${BLUE}[1/6] Hostname Display Identifier (VPS_NAME)${PLAIN}"
        echo -e "Desc: Used to differentiate multiple servers; shown in Telegram card header."
        read -p "Enter display name for this VPS [Default: $DEFAULT_VPS_NAME]: " VPS_NAME
    fi
    VPS_NAME=${VPS_NAME:-$DEFAULT_VPS_NAME}

    # Limit GB
    if [ "$MONITOR_LANG" = "zh" ]; then
        echo -e "\n${BLUE}[2/6] 月度流量限制总额 (LIMIT_GB)${PLAIN}"
        echo -e "说明: VPS 商家提供的月度总流量限制数 (单位: GB)。"
        read -p "请输入限制额度 [默认: $DEFAULT_LIMIT_GB]: " LIMIT_GB
    else
        echo -e "\n${BLUE}[2/6] Monthly Traffic Quota (LIMIT_GB)${PLAIN}"
        echo -e "Desc: The total monthly traffic limit provided by the VPS provider in GB."
        read -p "Enter quota limit [Default: $DEFAULT_LIMIT_GB]: " LIMIT_GB
    fi
    LIMIT_GB=${LIMIT_GB:-$DEFAULT_LIMIT_GB}
    if ! [[ "$LIMIT_GB" =~ ^[0-9]+$ ]]; then
        LIMIT_GB=$DEFAULT_LIMIT_GB
    fi

    # Already used traffic this month (one-time offset)
    if [ "$MONITOR_LANG" = "zh" ]; then
        echo -e "\n${BLUE}[2.5/6] 本月已使用流量 (INITIAL_USED_GB)${PLAIN}"
        echo -e "说明: 安装 vnstat 前本月已消耗的流量，用于补偿初始统计偏差 (单位: GB)。"
        echo -e "💡 仅首次运行时会加总一次，随后自动归零。"
        read -p "请输入安装前本月已用流量 [默认: $DEFAULT_INITIAL_USED]: " INITIAL_USED_GB
    else
        echo -e "\n${BLUE}[2.5/6] Initial Used This Month (INITIAL_USED_GB)${PLAIN}"
        echo -e "Desc: Traffic already consumed this billing cycle before vnstat was installed (in GB)."
        echo -e "💡 One-time offset — applied on first run, then auto-resets to 0."
        read -p "Enter already-used traffic this month [Default: $DEFAULT_INITIAL_USED]: " INITIAL_USED_GB
    fi
    INITIAL_USED_GB=${INITIAL_USED_GB:-$DEFAULT_INITIAL_USED}
    if ! [[ "$INITIAL_USED_GB" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        INITIAL_USED_GB=$DEFAULT_INITIAL_USED
    fi

    # Alert Threshold
    if [ "$MONITOR_LANG" = "zh" ]; then
        echo -e "\n${BLUE}[3/6] 起始报警阈值比例 (ALERT_THRESHOLD)${PLAIN}"
        echo -e "说明: 流量消耗达到此百分比时开始报警，超量后还会阶梯式在 90%、95%、100% 时各告警一次。"
        read -p "请输入起始警报比例 (0-100) [默认: $DEFAULT_ALERT_THRESHOLD]: " ALERT_THRESHOLD
    else
        echo -e "\n${BLUE}[3/6] Start Alert Threshold Percentage (ALERT_THRESHOLD)${PLAIN}"
        echo -e "Desc: Starts alert when traffic reaches this range percent. Alerts will trigger again at 90%, 95%, 100%."
        read -p "Enter start warning threshold (0-100) [Default: $DEFAULT_ALERT_THRESHOLD]: " ALERT_THRESHOLD
    fi
    ALERT_THRESHOLD=${ALERT_THRESHOLD:-$DEFAULT_ALERT_THRESHOLD}
    if ! [[ "$ALERT_THRESHOLD" =~ ^[0-9]+$ ]] || [ "$ALERT_THRESHOLD" -lt 0 ] || [ "$ALERT_THRESHOLD" -gt 100 ]; then
        ALERT_THRESHOLD=$DEFAULT_ALERT_THRESHOLD
    fi

    # Reset Day
    if [ "$MONITOR_LANG" = "zh" ]; then
        echo -e "\n${BLUE}[4/6] 账单重置日期 (RESET_DAY)${PLAIN}"
        echo -e "说明: 你的 VPS 账单流量重置日(如每月 22 号)。"
        echo -e "⚠️  受 vnstat 底层月份天数兼容设计限制，只能设置为 1-28 号。"
        read -p "请输入每月重置日期 (1-28) [默认: $DEFAULT_RESET_DAY]: " RESET_DAY
    else
        echo -e "\n${BLUE}[4/6] Billing Cycle Reset Day (RESET_DAY)${PLAIN}"
        echo -e "Desc: The day of the month your quota resets (e.g. 22nd)."
        echo -e "⚠️  Limited by vnstat month structure compatibilities, value must be between 1 and 28."
        read -p "Enter billing reset day (1-28) [Default: $DEFAULT_RESET_DAY]: " RESET_DAY
    fi
    RESET_DAY=${RESET_DAY:-$DEFAULT_RESET_DAY}
    if ! [[ "$RESET_DAY" =~ ^[0-9]+$ ]] || [ "$RESET_DAY" -lt 1 ] || [ "$RESET_DAY" -gt 28 ]; then
        if [ "$MONITOR_LANG" = "zh" ]; then
            echo -e "${RED}输入无效，默认回退到 $DEFAULT_RESET_DAY 号。${PLAIN}"
        else
            echo -e "${RED}Invalid input, reverting back to defaults: Day $DEFAULT_RESET_DAY.${PLAIN}"
        fi
        RESET_DAY=$DEFAULT_RESET_DAY
    fi

    # Daily Report Setting
    if [ "$MONITOR_LANG" = "zh" ]; then
        echo -e "\n${BLUE}[5/6] 每日例行流量总结报告 (DAILY_REPORT)${PLAIN}"
        echo -e "说明: 每天定时向你汇报当前已用/剩余流量总结。"
        read -p "是否开启运行报告? (y/n) [默认: $DEFAULT_DAILY]: " WANT_DAILY
    else
        echo -e "\n${BLUE}[5/6] Daily Routine Traffic Report (DAILY_REPORT)${PLAIN}"
        echo -e "Desc: Receive a scheduled daily notification containing current usage metrics."
        read -p "Enable scheduled daily reports? (y/n) [Default: $DEFAULT_DAILY]: " WANT_DAILY
    fi
    WANT_DAILY=${WANT_DAILY:-$DEFAULT_DAILY}
    if [[ "$WANT_DAILY" =~ ^[Nn]$ ]]; then
        DAILY_REPORT=false
        DAILY_REPORT_HOUR=9
    else
        DAILY_REPORT=true
        if [ "$MONITOR_LANG" = "zh" ]; then
            read -p "   请输入每天定时推送的时间 (整点小时 0-23) [默认: $DEFAULT_DAILY_HOUR]: " DAILY_HOUR
        else
            read -p "   Enter daily scheduled report hour (0-23) [Default: $DEFAULT_DAILY_HOUR]: " DAILY_HOUR
        fi
        DAILY_REPORT_HOUR=${DAILY_HOUR:-$DEFAULT_DAILY_HOUR}
        if ! [[ "$DAILY_REPORT_HOUR" =~ ^[0-9]+$ ]] || [ "$DAILY_REPORT_HOUR" -lt 0 ] || [ "$DAILY_REPORT_HOUR" -gt 23 ]; then
            DAILY_REPORT_HOUR=$DEFAULT_DAILY_HOUR
        fi
    fi

    # Telegram Credentials
    if [ "$MONITOR_LANG" = "zh" ]; then
        echo -e "\n${YELLOW}配置 Telegram 机器人凭证信息:${PLAIN}"
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
    else
        echo -e "\n${YELLOW}Configure Telegram Bot Credentials:${PLAIN}"
        if [ -n "$DEFAULT_TG_TOKEN" ]; then
            read -p "Telegram Bot Token [Default: $DEFAULT_TG_TOKEN]: " TG_TOKEN
            TG_TOKEN=${TG_TOKEN:-$DEFAULT_TG_TOKEN}
        else
            read -p "Telegram Bot Token: " TG_TOKEN
        fi

        if [ -n "$DEFAULT_TG_CHAT" ]; then
            read -p "Telegram Chat ID [Default: $DEFAULT_TG_CHAT]: " TG_CHAT
            TG_CHAT=${TG_CHAT:-$DEFAULT_TG_CHAT}
        else
            read -p "Telegram Chat ID: " TG_CHAT
        fi
    fi

    # Active Poll Command Listener Service Ask
    if [ "$MONITOR_LANG" = "zh" ]; then
        echo -e "\n${BLUE}[6/6] 选填: 开启后台 Telegram 命令主动查询服务 (/traffic) ${PLAIN}"
        echo -e "说明: 开启后将在后台运行极轻量的监听服务，您可以直接给 Bot 发送 /traffic 或 /status 实时调取流量卡片。"
        echo -e "💡 基本上不消耗 CPU，运行内存低于 5MB。"
        read -p "是否开启此主动指令查询服务？ (y/n) [默认: $DEFAULT_ENABLE_LISTENER]: " WANT_LISTENER
    else
        echo -e "\n${BLUE}[6/6] Optional: Active Telegram Command (/traffic) Listener Service${PLAIN}"
        echo -e "Desc: Runs a lightweight daemon. You can send /traffic or /status to get your usage card anytime."
        echo -e "💡 Virtually zero CPU overhead; RAM usage is under 5MB."
        read -p "Enable active command listener daemon? (y/n) [Default: $DEFAULT_ENABLE_LISTENER]: " WANT_LISTENER
    fi
    WANT_LISTENER=${WANT_LISTENER:-$DEFAULT_ENABLE_LISTENER}
    if [[ "$WANT_LISTENER" =~ ^[Yy]$ ]]; then
        ENABLE_LISTENER="true"
    else
        ENABLE_LISTENER="false"
    fi

    # Write configs to config.env
    cat <<EOF > "$CONFIG_FILE"
# Language Setting (en/zh) | 监控语言设置 (en/zh)
MONITOR_LANG="${MONITOR_LANG}"

# Telegram Bot Token
TELEGRAM_BOT_TOKEN="${TG_TOKEN}"

# Telegram Chat ID or Group ID
TELEGRAM_CHAT_ID="${TG_CHAT}"

# VPS Total monthly traffic limit in GB
LIMIT_GB=${LIMIT_GB}

# Already used traffic this billing cycle before installing monitor (GB).
# Inputted by user during installation, utilized on first run to compute INITIAL_OFFSET_GB.
INITIAL_USED_GB=${INITIAL_USED_GB}

# Internal auto-calculated offset (GB) to compensate for pre-installation usage.
INITIAL_OFFSET_GB=0.00

# The billing month when the initial offset was recorded (Format: YYYY-MM).
INITIAL_OFFSET_MONTH=""

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
        # Remove all existing MonthRotate lines, then append the new one
        sed -i '/MonthRotate/d' "$VNSTAT_CONF"
        echo "MonthRotate $RESET_DAY" >> "$VNSTAT_CONF"
        # Restart vnstat service
        systemctl restart vnstat 2>/dev/null
    fi
else
    # Config is kept, load values to display summary
    source "$CONFIG_FILE"
    RESET_DAY=$(grep -E "^MonthRotate" /etc/vnstat.conf | head -n 1 | awk '{print $2}')
    RESET_DAY=${RESET_DAY:-1}
    TG_TOKEN=$TELEGRAM_BOT_TOKEN
    TG_CHAT=$TELEGRAM_CHAT_ID
    # Check if systemd listener service is active
    if systemctl is-active vps-traffic-listener.service &>/dev/null; then
        ENABLE_LISTENER="true"
    else
        ENABLE_LISTENER="false"
    fi
fi

# 5. Setup Cron Job
if [ "$MONITOR_LANG" = "zh" ]; then
    echo -e "\n${YELLOW}步骤 4: 设置定时检查 Cron 定时任务 (每 5 分钟无感运行)...${PLAIN}"
else
    echo -e "\n${YELLOW}Step 4: Setting up Cron Job (Runs every 5 Minutes)...${PLAIN}"
fi
CRON_CMD="*/5 * * * * /bin/bash $MONITOR_SCRIPT > /dev/null 2>&1"

# Check if cron job already exists to avoid duplicates
(crontab -l 2>/dev/null | grep -F "$MONITOR_SCRIPT" >/dev/null)
if [ $? -eq 0 ]; then
    if [ "$MONITOR_LANG" = "zh" ]; then
        echo -e "已存在定时重轮询任务，自动跳过。"
    else
        echo -e "Cron job already exists. Skipping."
    fi
else
    (crontab -l 2>/dev/null; echo "$CRON_CMD") | crontab -
    if [ "$MONITOR_LANG" = "zh" ]; then
        echo -e "成功设定 Cron 执行任务: ${GREEN}每 5 分钟${PLAIN}"
    else
        echo -e "Cron job scheduled: ${GREEN}Every 5 Minutes${PLAIN}"
    fi
fi

# 6. Setup Active Polling daemon in systemd if enabled
LISTENER_SERVICE_FILE="/etc/systemd/system/vps-traffic-listener.service"
if [ "$ENABLE_LISTENER" = "true" ]; then
    if [ "$MONITOR_LANG" = "zh" ]; then
        echo -e "\n${YELLOW}步骤 5: 正在安装并配置系统守护服务 (vps-traffic-listener.service)...${PLAIN}"
    else
        echo -e "\n${YELLOW}Step 5: Installing and configuring listener daemon (vps-traffic-listener.service)...${PLAIN}"
    fi

    # Write systemd service file
    cat <<EOF > "$LISTENER_SERVICE_FILE"
[Unit]
Description=VPS Traffic Monitor Telegram Bot Listener
After=network.target

[Service]
Type=simple
WorkingDirectory=${INSTALL_DIR}
ExecStart=/bin/bash ${LISTENER_SCRIPT}
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd and start service
    systemctl daemon-reload
    systemctl enable vps-traffic-listener.service
    systemctl restart vps-traffic-listener.service
    if [ "$MONITOR_LANG" = "zh" ]; then
        echo -e "${GREEN}监听服务已成功安装，以 systemd 开机自启状态启动。${PLAIN}"
    else
        echo -e "${GREEN}Listener service successfully installed and started under systemd. Enabled at boot.${PLAIN}"
    fi
else
    # Disable and stop service if it was running previously
    if [ -f "$LISTENER_SERVICE_FILE" ]; then
        systemctl stop vps-traffic-listener.service 2>/dev/null
        systemctl disable vps-traffic-listener.service 2>/dev/null
        rm -f "$LISTENER_SERVICE_FILE"
        systemctl daemon-reload
        if [ "$MONITOR_LANG" = "zh" ]; then
            echo -e "\n${YELLOW}已停止并关闭之前的后台监听守护进程。${PLAIN}"
        else
            echo -e "\n${YELLOW}Stopped and disabled previous listener daemon service. Skipping.${PLAIN}"
        fi
    fi
fi

# Show structural summary report
echo -e "\n${GREEN}===============================================${PLAIN}"
if [ "$MONITOR_LANG" = "zh" ]; then
    echo -e "${GREEN}             软件安装与配置已完成!             ${PLAIN}"
    echo -e "${GREEN}===============================================${PLAIN}"
    echo -e "\n${BLUE}=== VPS 流量监视配置清单 ===${PLAIN}"
    echo -e "• 语言设定:      ${YELLOW}${MONITOR_LANG}${PLAIN}"
    echo -e "• VPS 识别名称:  ${YELLOW}${VPS_NAME}${PLAIN}"
    echo -e "• 流量配额限额:  ${YELLOW}${LIMIT_GB} GB${PLAIN}"
    if [ "$INITIAL_USED_GB" -gt 0 ]; then
        echo -e "• 本月已用补偿:  ${YELLOW}${INITIAL_USED_GB} GB${PLAIN} (一次性，首次运行后归零)"
    fi
    echo -e "• 警报限额比例:  ${YELLOW}${ALERT_THRESHOLD}%${PLAIN}"
    echo -e "• 账单重置周期:  每月 ${YELLOW}${RESET_DAY}${PLAIN} 号 (通过 vnstat)"
    echo -e "• 每日例行总结:  ${YELLOW}${DAILY_REPORT}${PLAIN}"
    if [ "$DAILY_REPORT" = "true" ]; then
        echo -e "  └─ 定时发送小时: 每天 ${YELLOW}${DAILY_REPORT_HOUR}:00${PLAIN}"
    fi
    echo -e "• 主动指令查询:  ${YELLOW}${ENABLE_LISTENER}${PLAIN} (向 Bot 发送 /traffic 触发)"
    echo -e "• TG Token:      ${YELLOW}${TG_TOKEN:-(未配置)}${PLAIN}"
    echo -e "• TG Chat ID:    ${YELLOW}${TG_CHAT:-(未配置)}${PLAIN}"
    echo -e "• 安装绝对目录:  ${YELLOW}${INSTALL_DIR}${PLAIN}"
    echo -e "• 本地卸载脚本:  ${YELLOW}${INSTALL_DIR}/uninstall.sh${PLAIN}"
    echo -e "==========================================="
else
    echo -e "${GREEN}     Installation Complete successfully!       ${PLAIN}"
    echo -e "${GREEN}===============================================${PLAIN}"
    echo -e "\n${BLUE}=== VPS Traffic Monitor Configurations ===${PLAIN}"
    echo -e "• Monitor Language: ${YELLOW}${MONITOR_LANG}${PLAIN}"
    echo -e "• VPS ID/Name:      ${YELLOW}${VPS_NAME}${PLAIN}"
    echo -e "• Traffic Limit:    ${YELLOW}${LIMIT_GB} GB${PLAIN}"
    if [ "$INITIAL_USED_GB" -gt 0 ]; then
        echo -e "• Initial Offset:   ${YELLOW}${INITIAL_USED_GB} GB${PLAIN} (one-time, auto-resets after first run)"
    fi
    echo -e "• Alert Threshold:  ${YELLOW}${ALERT_THRESHOLD}%${PLAIN}"
    echo -e "• Billing Reset:    Monthly Day ${YELLOW}${RESET_DAY}${PLAIN} (via vnstat)"
    echo -e "• Daily Report:     ${YELLOW}${DAILY_REPORT}${PLAIN}"
    if [ "$DAILY_REPORT" = "true" ]; then
        echo -e "  └─ Daily Report Hour: ${YELLOW}${DAILY_REPORT_HOUR}:00${PLAIN}"
    fi
    echo -e "• Active Command:   ${YELLOW}${ENABLE_LISTENER}${PLAIN} (Send /traffic to your Bot)"
    echo -e "• TG Token:         ${YELLOW}${TG_TOKEN:-(Not Configured)}${PLAIN}"
    echo -e "• TG Chat ID:       ${YELLOW}${TG_CHAT:-(Not Configured)}${PLAIN}"
    echo -e "• Absolute Path:    ${YELLOW}${INSTALL_DIR}${PLAIN}"
    echo -e "• Local Uninstaller: ${YELLOW}${INSTALL_DIR}/uninstall.sh${PLAIN}"
    echo -e "==========================================="
fi

# Automatically trigger channel test if credentials are supplied
if [ -n "$TG_TOKEN" ] && [ -n "$TG_CHAT" ]; then
    if [ "$MONITOR_LANG" = "zh" ]; then
        echo -e "\n${YELLOW}正在向您的 Telegram 发出包含实时流量的测试消息卡片...${PLAIN}"
        /bin/bash "$MONITOR_SCRIPT" test
        echo -e "\n📢 ${GREEN}请立刻检查您的 Telegram 客户端，验证是否收到了上述测试图表！${PLAIN}"
        echo -e "💡 如果长时间未收到，代表您配置的 ${RED}Bot Token${PLAIN} 或 ${RED}Chat ID${PLAIN} 有误，请查验后重新运行安装程序进行修改。"
    else
        echo -e "\n${YELLOW}Sending real-time telemetry test message card to Telegram...${PLAIN}"
        /bin/bash "$MONITOR_SCRIPT" test
        echo -e "\n📢 ${GREEN}Please verify you received the test message on your Telegram client!${PLAIN}"
        echo -e "💡 If you did not receive any notify, it implies your ${RED}Telegram Bot Token${PLAIN} or ${RED}Chat ID${PLAIN} might be incorrect. Re-run installation script to fix it."
    fi
fi

# Manual test instructions
if [ "$MONITOR_LANG" = "zh" ]; then
    echo -e "\n💡 ${YELLOW}提示：随时可以运行此命令手动发出流量通知测试：${PLAIN}"
    echo -e "   ${GREEN}${MONITOR_SCRIPT} test${PLAIN}"
else
    echo -e "\n💡 ${YELLOW}Tip: You can manually send another test notification at any time:${PLAIN}"
    echo -e "   ${GREEN}${MONITOR_SCRIPT} test${PLAIN}"
fi
