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
LIMIT_GB=${LIMIT_GB:-600}
ALERT_THRESHOLD=${ALERT_THRESHOLD:-80}
STATE_DIR=${STATE_DIR:-"/tmp"}
VPS_NAME=${VPS_NAME:-$(hostname)}
DAILY_REPORT=${DAILY_REPORT:-false}
DAILY_REPORT_HOUR=${DAILY_REPORT_HOUR:-9}

# Auto-detect interface if empty
if [ -z "$INTERFACE" ]; then
    INTERFACE=$(ip route show | grep default | awk '{print $5}' | head -n 1)
    if [ -z "$INTERFACE" ]; then
        echo "Error: Could not auto-detect default network interface." >&2
        exit 1
    fi
fi

# State files
ALERT_STATE_FILE="${STATE_DIR}/vps_traffic_alert_${INTERFACE}.state"
DAILY_STATE_FILE="${STATE_DIR}/vps_traffic_daily_${INTERFACE}.state"

send_tg_notification() {
    local text="$1"
    if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
        # Use http proxy if needed (can be customized by users if they have a proxy)
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
            -d "chat_id=${TELEGRAM_CHAT_ID}" \
            -d "parse_mode=Markdown" \
            -d "text=${text}" > /dev/null
    else
        echo "Telegram credentials not configured." >&2
    fi
}

# Handle manual test execution
if [ "$1" = "test" ] || [ "$1" = "--test" ]; then
    echo "Sending test Telegram notification..."
    TEST_MESSAGE="🔔 *VPS 流量监控测试通知* ($VPS_NAME)
━━━━━━━━━━━━━━━━━━
• *网卡名称*: $INTERFACE (测试)
• *当前状态*: 链路测试成功 ✅
• *测试时间*: $(date '+%Y-%m-%d %H:%M:%S')

_这是一条手动触发的测试通知，代表你的 Bot Token 与 Chat ID 配置正确！_"
    send_tg_notification "$TEST_MESSAGE"
    echo "Test message sent. Please check your Telegram."
    exit 0
fi

# Fetch vnstat monthly data (JSON mode)
VNSTAT_JSON=$(vnstat --json -i "$INTERFACE" 2>/dev/null)
if [ -z "$VNSTAT_JSON" ]; then
    echo "Error: Failed to query vnstat JSON data for interface $INTERFACE." >&2
    exit 1
fi

# Parsing json via jq
RX=$(echo "$VNSTAT_JSON" | jq '.interfaces[0].traffic.month[0].rx' 2>/dev/null)
TX=$(echo "$VNSTAT_JSON" | jq '.interfaces[0].traffic.month[0].tx' 2>/dev/null)

if [ "$RX" = "null" ] || [ -z "$RX" ]; then
    # Maybe vnstat has no monthly stats accumulated yet.
    # In older vnstat versions or fresh installs, month[0] might not contain data. Fall back to total or exit.
    echo "Warning: vnstat monthly stats not ready yet."
    exit 0
fi

TOTAL_BYTES=$((RX + TX))
# Calculate usage (Floating point emulation using bc)
USED_GB=$(echo "scale=2; $TOTAL_BYTES / 1073741824" | bc)
USED_PERCENT=$(echo "scale=0; ($TOTAL_BYTES * 100) / ($LIMIT_GB * 1073741824)" | bc)

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

# Format values for readable output in TG
RX_GB=$(echo "scale=2; $RX / 1073741824" | bc)
TX_GB=$(echo "scale=2; $TX / 1073741824" | bc)

# Trigger notifications if we moved to a higher alert stage
if [ "$CURRENT_STAGE" -gt "$LAST_STAGE" ]; then
    MESSAGE="⚠️ *VPS 流量告警通知* ($VPS_NAME)
━━━━━━━━━━━━━━━━━━
• *网卡名称*: $INTERFACE
• *下载流量 (RX)*: ${RX_GB} GB
• *上传流量 (TX)*: ${TX_GB} GB
• *算计已用*: *${USED_GB} GB*
• *流量配额*: ${LIMIT_GB} GB
• *消耗比例*: *${USED_PERCENT}%*
• *警告阈值*: ${CURRENT_STAGE}% 📈
• *账单重置*: 每月 22 号

_流量消耗已达到设定等级，请及时调整使用策略。_"

    send_tg_notification "$MESSAGE"
fi

# Reset state when usage drops below the alert thresholds (e.g., billing cycle resets)
if [ "$CURRENT_STAGE" -lt "$LAST_STAGE" ] || [ "$USED_PERCENT" -lt "$ALERT_THRESHOLD" ]; then
    if [ "$LAST_STAGE" -gt 0 ] && [ "$USED_PERCENT" -lt "$ALERT_THRESHOLD" ]; then
        RESET_MESSAGE="✅ *VPS 流量重置通知* ($VPS_NAME)
━━━━━━━━━━━━━━━━━━
• *网卡名称*: $INTERFACE
• *新周期已用*: ${USED_GB} GB
• *使用比例*: ${USED_PERCENT}%
• *账单重置*: 已于每月 22 号完成重置 ♻️"
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
            DAILY_MESSAGE="📊 *VPS 每日流量汇报* ($VPS_NAME)
━━━━━━━━━━━━━━━━━━
• *监控网卡*: $INTERFACE
• *下载流量 (RX)*: ${RX_GB} GB
• *上传流量 (TX)*: ${TX_GB} GB
• *合计已用*: *${USED_GB} GB* (共 ${LIMIT_GB} GB)
• *剩余流量*: $(echo "scale=2; $LIMIT_GB - $USED_GB" | bc) GB
• *使用空间*: *${USED_PERCENT}%*
• *计算周期*: 每月 22 号重置

_状态良好，监控运行中..._"

            send_tg_notification "$DAILY_MESSAGE"
            # Mark as sent for today
            echo "$CURRENT_DATE" > "$DAILY_STATE_FILE"
        fi
    fi
fi
