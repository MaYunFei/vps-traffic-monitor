#!/bin/bash

# Define absolute paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.env"

# Load config if exists
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "Error: Configuration file not found at $CONFIG_FILE" >&2
    exit 1
fi

# Set defaults
MONITOR_LANG=${MONITOR_LANG:-"en"}
LIMIT_GB=${LIMIT_GB:-1000}
ALERT_THRESHOLD=${ALERT_THRESHOLD:-80}
STATE_DIR=${STATE_DIR:-"/tmp"}
VPS_NAME=${VPS_NAME:-$(hostname)}
DAILY_REPORT=${DAILY_REPORT:-false}
DAILY_REPORT_HOUR=${DAILY_REPORT_HOUR:-9}

# Auto-detect interface if empty
if [ -z "$INTERFACE" ]; then
    INTERFACE=$(ip route show | grep default | awk '{print $5}' | head -n 1)
    if [ -z "$INTERFACE" ]; then
        if [ "$MONITOR_LANG" = "zh" ]; then
            echo "错误: 无法自动检测默认网络接口。" >&2
        else
            echo "Error: Could not auto-detect default network interface." >&2
        fi
        exit 1
    fi
fi

# State files
ALERT_STATE_FILE="${STATE_DIR}/vps_traffic_alert_${INTERFACE}.state"
DAILY_STATE_FILE="${STATE_DIR}/vps_traffic_daily_${INTERFACE}.state"

# Read Reset Day from vnstat.conf if available
RESET_DAY=$(grep -E "^MonthRotate" /etc/vnstat.conf 2>/dev/null | awk '{print $2}')
RESET_DAY=${RESET_DAY:-1}

send_tg_notification() {
    local text="$1"
    local target_chat="${2:-$TELEGRAM_CHAT_ID}"
    if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$target_chat" ]; then
        # Use http proxy if needed (can be customized by users if they have a proxy)
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
            -d "chat_id=${target_chat}" \
            -d "parse_mode=Markdown" \
            -d "text=${text}" > /dev/null
    else
        if [ "$MONITOR_LANG" = "zh" ]; then
            echo "未配置 Telegram 凭据。" >&2
        else
            echo "Telegram credentials not configured." >&2
        fi
    fi
}

# Fetch vnstat monthly data (JSON mode)
VNSTAT_JSON=$(vnstat --json -i "$INTERFACE" 2>/dev/null)
if [ -z "$VNSTAT_JSON" ]; then
    if [ "$MONITOR_LANG" = "zh" ]; then
        echo "错误: 无法为网卡 $INTERFACE 查询 vnstat JSON 流量数据。" >&2
    else
        echo "Error: Failed to query vnstat JSON data for interface $INTERFACE." >&2
    fi
    exit 1
fi

# Parsing json via jq
RX=$(echo "$VNSTAT_JSON" | jq '.interfaces[0].traffic.month[0].rx' 2>/dev/null)
TX=$(echo "$VNSTAT_JSON" | jq '.interfaces[0].traffic.month[0].tx' 2>/dev/null)

# Fallback values if stats are not ready yet
if [ "$RX" = "null" ] || [ -z "$RX" ]; then
    RX=0
fi
if [ "$TX" = "null" ] || [ -z "$TX" ]; then
    TX=0
fi

TOTAL_BYTES=$((RX + TX))
# Calculate usage (Floating point emulation using bc)
USED_GB=$(echo "scale=2; $TOTAL_BYTES / 1073741824" | bc)
USED_PERCENT=$(echo "scale=0; ($TOTAL_BYTES * 100) / ($LIMIT_GB * 1073741824)" | bc)

# Format values for readable output in TG
RX_GB=$(echo "scale=2; $RX / 1073741824" | bc)
TX_GB=$(echo "scale=2; $TX / 1073741824" | bc)

generate_message() {
    local type="$1"
    local current_stage="$2"
    local message=""
    if [ "$MONITOR_LANG" = "zh" ]; then
        case "$type" in
            test)
                message="🔔 *VPS 流量监控测试通知* ($VPS_NAME)
━━━━━━━━━━━━━━━━━━
• *监控网卡*: $INTERFACE
• *下载流量 (RX)*: ${RX_GB} GB
• *上传流量 (TX)*: ${TX_GB} GB
• *合计已用*: *${USED_GB} GB* (共 ${LIMIT_GB} GB)
• *使用比例*: *${USED_PERCENT}%*
• *计算周期*: 每月 ${RESET_DAY} 号重置"
                ;;
            alert)
                message="⚠️ *VPS 流量告警通知* ($VPS_NAME)
━━━━━━━━━━━━━━━━━━
• *网卡名称*: $INTERFACE
• *下载流量 (RX)*: ${RX_GB} GB
• *上传流量 (TX)*: ${TX_GB} GB
• *合计已用*: *${USED_GB} GB*
• *流量配额*: ${LIMIT_GB} GB
• *消耗比例*: *${USED_PERCENT}%*
• *警告阈值*: ${current_stage}% 📈
• *账单重置*: 每月 ${RESET_DAY} 号

_流量消耗已达到设定等级，请及时调整使用策略。_"
                ;;
            reset)
                message="✅ *VPS 流量重置通知* ($VPS_NAME)
━━━━━━━━━━━━━━━━━━
• *网卡名称*: $INTERFACE
• *新周期已用*: ${USED_GB} GB
• *使用比例*: ${USED_PERCENT}%
• *账单重置*: 已于每月 ${RESET_DAY} 号完成重置 ♻️"
                ;;
            daily)
                local remaining_gb=$(echo "scale=2; $LIMIT_GB - $USED_GB" | bc)
                message="📊 *VPS 每日流量汇报* ($VPS_NAME)
━━━━━━━━━━━━━━━━━━
• *监控网卡*: $INTERFACE
• *下载流量 (RX)*: ${RX_GB} GB
• *上传流量 (TX)*: ${TX_GB} GB
• *合计已用*: *${USED_GB} GB* (共 ${LIMIT_GB} GB)
• *剩余流量*: ${remaining_gb} GB
• *使用比例*: *${USED_PERCENT}%*
• *计算周期*: 每月 ${RESET_DAY} 号重置

_状态良好，监控运行中..._"
                ;;
            query)
                message="📊 *VPS 流量实时状态* ($VPS_NAME)
━━━━━━━━━━━━━━━━━━
• *监控网卡*: $INTERFACE
• *下载流量 (RX)*: ${RX_GB} GB
• *上传流量 (TX)*: ${TX_GB} GB
• *合计已用*: *${USED_GB} GB* (共 ${LIMIT_GB} GB)
• *使用比例*: *${USED_PERCENT}%*
• *计算周期*: 每月 ${RESET_DAY} 号重置"
                ;;
        esac
    else
        case "$type" in
            test)
                message="🔔 *VPS Traffic Monitor Test* ($VPS_NAME)
━━━━━━━━━━━━━━━━━━
• *Interface*: $INTERFACE
• *Download (RX)*: ${RX_GB} GB
• *Upload (TX)*: ${TX_GB} GB
• *Total Used*: *${USED_GB} GB* (of ${LIMIT_GB} GB)
• *Usage Ratio*: *${USED_PERCENT}%*
• *Billing Cycle*: Monthly day ${RESET_DAY}"
                ;;
            alert)
                message="⚠️ *VPS Traffic Alert* ($VPS_NAME)
━━━━━━━━━━━━━━━━━━
• *Interface*: $INTERFACE
• *Download (RX)*: ${RX_GB} GB
• *Upload (TX)*: ${TX_GB} GB
• *Total Used*: *${USED_GB} GB*
• *Quota*: ${LIMIT_GB} GB
• *Usage Ratio*: *${USED_PERCENT}%*
• *Threshold*: ${current_stage}% 📈
• *Billing Cycle*: Monthly day ${RESET_DAY}

_Traffic consumption has reached the threshold. Adjust usage accordingly._"
                ;;
            reset)
                message="✅ *VPS Traffic Reset* ($VPS_NAME)
━━━━━━━━━━━━━━━━━━
• *Interface*: $INTERFACE
• *New Term Used*: ${USED_GB} GB
• *Usage Ratio*: ${USED_PERCENT}%
• *Billing Cycle*: Reset on monthly day ${RESET_DAY} ♻️"
                ;;
            daily)
                local remaining_gb=$(echo "scale=2; $LIMIT_GB - $USED_GB" | bc)
                message="📊 *VPS Daily Traffic Report* ($VPS_NAME)
━━━━━━━━━━━━━━━━━━
• *Interface*: $INTERFACE
• *Download (RX)*: ${RX_GB} GB
• *Upload (TX)*: ${TX_GB} GB
• *Total Used*: *${USED_GB} GB* (of ${LIMIT_GB} GB)
• *Remaining*: ${remaining_gb} GB
• *Usage Ratio*: *${USED_PERCENT}%*
• *Billing Cycle*: Monthly day ${RESET_DAY}

_Status is good, monitoring active..._"
                ;;
            query)
                message="📊 *VPS Real-time Traffic Status* ($VPS_NAME)
━━━━━━━━━━━━━━━━━━
• *Interface*: $INTERFACE
• *Download (RX)*: ${RX_GB} GB
• *Upload (TX)*: ${TX_GB} GB
• *Total Used*: *${USED_GB} GB* (of ${LIMIT_GB} GB)
• *Usage Ratio*: *${USED_PERCENT}%*
• *Billing Cycle*: Monthly day ${RESET_DAY}"
                ;;
        esac
    fi
    echo "$message"
}

# Handle manual test execution
if [ "$1" = "test" ] || [ "$1" = "--test" ]; then
    if [ "$MONITOR_LANG" = "zh" ]; then
        echo "正在向 Telegram 发送包含实时数据的测试通知..."
    else
        echo "Sending test Telegram notification with real statistics..."
    fi
    TEST_MESSAGE=$(generate_message "test")
    send_tg_notification "$TEST_MESSAGE"
    if [ "$MONITOR_LANG" = "zh" ]; then
        echo "测试消息已发送，请检查您的 Telegram。"
    else
        echo "Test message sent. Please check your Telegram."
    fi
    exit 0
fi

# Handle active query execution
if [ "$1" = "query" ] || [ "$1" = "--query" ]; then
    QUERY_MESSAGE=$(generate_message "query")
    target_chat="$2"
    send_tg_notification "$QUERY_MESSAGE" "${target_chat:-$TELEGRAM_CHAT_ID}"
    exit 0
fi

if [ "$RX" = "0" ] && [ "$TOTAL_BYTES" = "0" ]; then
    # Maybe vnstat has no monthly stats accumulated yet.
    # In older vnstat versions or fresh installs, month[0] might not contain data. Fall back to total or exit.
    if [ "$MONITOR_LANG" = "zh" ]; then
        echo "警告: vnstat 月度流量统计数据尚未就绪。"
    else
        echo "Warning: vnstat monthly stats not ready yet."
    fi
    exit 0
fi

# Multi-stage thresholds implementation: 80% -> 90% -> 95% -> 100%
CURRENT_STAGE=0
if [ "$USED_PERCENT" -ge 100 ]; then
    CURRENT_STAGE=100
elif [ "$USED_PERCENT" -ge 95 ]; then
    CURRENT_STAGE=95
elif [ "$USED_PERCENT" -ge 90 ]; then
    CURRENT_STAGE=90
elif [ "$USED_PERCENT" -ge "$ALERT_THRESHOLD" ]; then
    CURRENT_STAGE="$ALERT_THRESHOLD"
fi

# Load last alert level
LAST_STAGE=0
if [ -f "$ALERT_STATE_FILE" ]; then
    LAST_STAGE=$(cat "$ALERT_STATE_FILE")
    # Quick sanity check
    if ! [[ "$LAST_STAGE" =~ ^[0-9]+$ ]]; then
        LAST_STAGE=0
    fi
fi

# Trigger notifications if we moved to a higher alert stage
if [ "$CURRENT_STAGE" -gt "$LAST_STAGE" ]; then
    MESSAGE=$(generate_message "alert" "$CURRENT_STAGE")
    send_tg_notification "$MESSAGE"
fi

# Reset state when usage drops below the alert thresholds (e.g., billing cycle resets)
if [ "$CURRENT_STAGE" -lt "$LAST_STAGE" ] || [ "$USED_PERCENT" -lt "$ALERT_THRESHOLD" ]; then
    if [ "$LAST_STAGE" -gt 0 ] && [ "$USED_PERCENT" -lt "$ALERT_THRESHOLD" ]; then
        RESET_MESSAGE=$(generate_message "reset")
        send_tg_notification "$RESET_MESSAGE"
    fi
fi

# Persist the current stage
echo "$CURRENT_STAGE" > "$ALERT_STATE_FILE"

# Daily Report Summary Logic
if [ "$DAILY_REPORT" = "true" ]; then
    CURRENT_HOUR=$(date '+%H')
    CURRENT_DATE=$(date '+%Y-%m-%d')
    # Strip leading zero if any to prevent octal issue in bash comparison
    CURRENT_HOUR_INT=$((10#$CURRENT_HOUR))
    TARGET_HOUR_INT=$((10#$DAILY_REPORT_HOUR))

    if [ "$CURRENT_HOUR_INT" -eq "$TARGET_HOUR_INT" ]; then
        LAST_DAILY_DATE=""
        if [ -f "$DAILY_STATE_FILE" ]; then
            LAST_DAILY_DATE=$(cat "$DAILY_STATE_FILE")
        fi

        # If we haven't sent the report today
        if [ "$LAST_DAILY_DATE" != "$CURRENT_DATE" ]; then
            DAILY_MESSAGE=$(generate_message "daily")
            send_tg_notification "$DAILY_MESSAGE"
            # Mark as sent for today
            echo "$CURRENT_DATE" > "$DAILY_STATE_FILE"
        fi
    fi
fi
