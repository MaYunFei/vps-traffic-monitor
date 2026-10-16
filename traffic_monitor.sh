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
DAILY_REPORT_HOUR=${DAILY_REPORT_HOUR:-21}
INITIAL_USED_GB=${INITIAL_USED_GB:-0}
INITIAL_OFFSET_GB=${INITIAL_OFFSET_GB:-0.00}
INITIAL_OFFSET_MONTH=${INITIAL_OFFSET_MONTH:-""}

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
MONTH_STATE_FILE="${STATE_DIR}/vps_traffic_month_${INTERFACE}.state"

# Read Reset Day from vnstat.conf if available
RESET_DAY=$(grep -E "^MonthRotate" /etc/vnstat.conf 2>/dev/null | awk '{print $2}')
RESET_DAY=${RESET_DAY:-1}

send_tg_notification() {
    local text="$1"
    local target_chat="${2:-$TELEGRAM_CHAT_ID}"
    if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$target_chat" ]; then
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

# Ensure vnstat daemon is active, self-heal if stopped
if command -v systemctl >/dev/null 2>&1 && ! systemctl is-active --quiet vnstat; then
    systemctl restart vnstat 2>/dev/null || true
    sleep 1
fi

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

# Parsing json via jq to dynamically determine current billing cycle
TODAY_YEAR=$(date '+%Y')
TODAY_MONTH=$(date '+%m')
TODAY_DAY=$(date '+%d')

TODAY_YEAR_INT=$((10#$TODAY_YEAR))
TODAY_MONTH_INT=$((10#$TODAY_MONTH))
TODAY_DAY_INT=$((10#$TODAY_DAY))
RESET_DAY_INT=$((10#$RESET_DAY))

if [ "$TODAY_DAY_INT" -ge "$RESET_DAY_INT" ]; then
    BILL_YEAR=$TODAY_YEAR_INT
    BILL_MONTH=$TODAY_MONTH_INT
else
    BILL_MONTH=$((TODAY_MONTH_INT - 1))
    BILL_YEAR=$TODAY_YEAR_INT
    if [ "$BILL_MONTH" -eq 0 ]; then
        BILL_MONTH=12
        BILL_YEAR=$((TODAY_YEAR_INT - 1))
    fi
fi

# Try to find target month data
MONTH_DATA=$(echo "$VNSTAT_JSON" | jq --argjson y "$BILL_YEAR" --argjson m "$BILL_MONTH" \
  '.interfaces[0].traffic.month[] | select(.date.year == $y and .date.month == $m)' 2>/dev/null)

if [ -z "$MONTH_DATA" ] || [ "$MONTH_DATA" = "null" ]; then
    # Fallback to the latest month entry in the list
    MONTH_DATA=$(echo "$VNSTAT_JSON" | jq '.interfaces[0].traffic.month[-1]' 2>/dev/null)
fi

RX=$(echo "$MONTH_DATA" | jq '.rx' 2>/dev/null)
TX=$(echo "$MONTH_DATA" | jq '.tx' 2>/dev/null)
YEAR_VAL=$(echo "$MONTH_DATA" | jq '.date.year' 2>/dev/null)
MONTH_VAL=$(echo "$MONTH_DATA" | jq '.date.month' 2>/dev/null)

# Fallback values if stats are not ready yet
if [ "$RX" = "null" ] || [ -z "$RX" ]; then
    RX=0
fi
if [ "$TX" = "null" ] || [ -z "$TX" ]; then
    TX=0
fi

if [ "$YEAR_VAL" = "null" ] || [ -z "$YEAR_VAL" ] || [ "$MONTH_VAL" = "null" ] || [ -z "$MONTH_VAL" ]; then
    CURRENT_BILL_MONTH=$(date '+%Y-%m')
else
    CURRENT_BILL_MONTH=$(printf "%04d-%02d" "$YEAR_VAL" "$MONTH_VAL")
fi

TOTAL_BYTES=$((RX + TX))
VNSTAT_USED_GB=$(echo "scale=4; $TOTAL_BYTES / 1073741824" | bc)

# 1. Check if we need to auto-calculate the initial offset
if [ -n "$INITIAL_USED_GB" ] && [ "$(echo "$INITIAL_USED_GB > 0" | bc)" -eq 1 ]; then
    # Calculate offset: user-provided total minus what vnstat already has recorded
    DIFF_OFFSET=$(echo "scale=4; $INITIAL_USED_GB - $VNSTAT_USED_GB" | bc)
    # Ensure offset is not negative
    if [ "$(echo "$DIFF_OFFSET < 0" | bc)" -eq 1 ]; then
        DIFF_OFFSET="0.00"
    fi
    # Format offset
    INITIAL_OFFSET_GB=$(printf "%.2f" "$DIFF_OFFSET")
    INITIAL_OFFSET_MONTH="$CURRENT_BILL_MONTH"

    # Save computed offset and reset the user input variable inside config.env
    sed -i "s/^INITIAL_USED_GB=.*/INITIAL_USED_GB=0/" "$CONFIG_FILE"
    sed -i "s/^INITIAL_OFFSET_GB=.*/INITIAL_OFFSET_GB=${INITIAL_OFFSET_GB}/" "$CONFIG_FILE"
    sed -i "s/^INITIAL_OFFSET_MONTH=.*/INITIAL_OFFSET_MONTH=\"${INITIAL_OFFSET_MONTH}\"/" "$CONFIG_FILE"
fi

# 2. Check if a new billing month has arrived to clear offset
if [ -n "$INITIAL_OFFSET_MONTH" ] && [ "$INITIAL_OFFSET_MONTH" != "$CURRENT_BILL_MONTH" ]; then
    INITIAL_OFFSET_GB="0.00"
    INITIAL_OFFSET_MONTH=""
    # Reset offsets in config.env block
    sed -i "s/^INITIAL_OFFSET_GB=.*/INITIAL_OFFSET_GB=0.00/" "$CONFIG_FILE"
    sed -i "s/^INITIAL_OFFSET_MONTH=.*/INITIAL_OFFSET_MONTH=\"\"/" "$CONFIG_FILE"
fi

# Calculate total usage including offset
USED_GB=$(echo "scale=2; $VNSTAT_USED_GB + $INITIAL_OFFSET_GB" | bc | awk '{printf "%.2f", $0}')

# Emulate USED_PERCENT calculating on total bytes equivalent
TOTAL_BYTES_OFFSET_EMULATED=$(echo "scale=0; ($TOTAL_BYTES + $INITIAL_OFFSET_GB * 1073741824) / 1" | bc)
USED_PERCENT=$(echo "scale=0; $TOTAL_BYTES_OFFSET_EMULATED * 100 / ($LIMIT_GB * 1073741824)" | bc)

# Format values for readable output in TG (Month totals)
RX_GB=$(echo "scale=2; $RX / 1073741824" | bc | awk '{printf "%.2f", $0}')
TX_GB=$(echo "scale=2; $TX / 1073741824" | bc | awk '{printf "%.2f", $0}')

# Fetch today's traffic statistics from vnstat JSON
TODAY_YEAR=$(date '+%Y')
TODAY_MONTH=$(date '+%m')
TODAY_DAY=$(date '+%d')

TODAY_DATA=$(echo "$VNSTAT_JSON" | jq --argjson y "$TODAY_YEAR" --argjson m "$((10#$TODAY_MONTH))" --argjson d "$((10#$TODAY_DAY))" \
  '.interfaces[0].traffic.day[] | select(.date.year == $y and .date.month == $m and .date.day == $d)' 2>/dev/null)

TODAY_RX=$(echo "$TODAY_DATA" | jq '.rx' 2>/dev/null)
TODAY_TX=$(echo "$TODAY_DATA" | jq '.tx' 2>/dev/null)

if [ "$TODAY_RX" = "null" ] || [ -z "$TODAY_RX" ]; then
    TODAY_RX=0
fi
if [ "$TODAY_TX" = "null" ] || [ -z "$TODAY_TX" ]; then
    TODAY_TX=0
fi

TODAY_TOTAL_BYTES=$((TODAY_RX + TODAY_TX))
TODAY_RX_GB=$(echo "scale=2; $TODAY_RX / 1073741824" | bc | awk '{printf "%.2f", $0}')
TODAY_TX_GB=$(echo "scale=2; $TODAY_TX / 1073741824" | bc | awk '{printf "%.2f", $0}')
TODAY_TOTAL_GB=$(echo "scale=2; $TODAY_TOTAL_BYTES / 1073741824" | bc | awk '{printf "%.2f", $0}')

generate_message() {
    local type="$1"
    local current_stage="$2"
    local message=""
    if [ "$MONITOR_LANG" = "zh" ]; then
        case "$type" in
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
• *结算账期*: 已完成每月 ${RESET_DAY} 号重置 ♻️"
                ;;
            daily)
                local remaining_gb=$(echo "scale=2; $LIMIT_GB - $USED_GB" | bc | awk '{printf "%.2f", $0}')
                message="📊 *VPS 每日流量汇报* ($VPS_NAME)
━━━━━━━━━━━━━━━━━━
• *监控网卡*: $INTERFACE
• *今日下载 (RX)*: ${TODAY_RX_GB} GB
• *今日上传 (TX)*: ${TODAY_TX_GB} GB
• *今日合计已用*: *${TODAY_TOTAL_GB} GB*
• *本期已用 (累计)*: *${USED_GB} GB* (共 ${LIMIT_GB} GB)
• *本期剩余流量*: ${remaining_gb} GB
• *使用比例*: *${USED_PERCENT}%*
• *结算账期*: 每月 ${RESET_DAY} 号重置

_状态良好，监控运行中..._"
                ;;
            query)
                message="📊 *VPS 流量实时状态* ($VPS_NAME)
━━━━━━━━━━━━━━━━━━
• *监控网卡*: $INTERFACE
• *今日下载 (RX)*: ${TODAY_RX_GB} GB
• *今日上传 (TX)*: ${TODAY_TX_GB} GB
• *今日合计已用*: *${TODAY_TOTAL_GB} GB*
• *本期已用 (累计)*: *${USED_GB} GB* (共 ${LIMIT_GB} GB)
• *使用比例*: *${USED_PERCENT}%*
• *结算账期*: 每月 ${RESET_DAY} 号重置"
                ;;
        esac
    else
        case "$type" in
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
                local remaining_gb=$(echo "scale=2; $LIMIT_GB - $USED_GB" | bc | awk '{printf "%.2f", $0}')
                message="📊 *VPS Daily Traffic Report* ($VPS_NAME)
━━━━━━━━━━━━━━━━━━
• *Interface*: $INTERFACE
• *Today Download (RX)*: ${TODAY_RX_GB} GB
• *Today Upload (TX)*: ${TODAY_TX_GB} GB
• *Today Total Used*: *${TODAY_TOTAL_GB} GB*
• *Cycle Total Used*: *${USED_GB} GB* (of ${LIMIT_GB} GB)
• *Cycle Remaining*: ${remaining_gb} GB
• *Usage Ratio*: *${USED_PERCENT}%*
• *Billing Cycle*: Monthly day ${RESET_DAY}

_Status is good, monitoring active..._"
                ;;
            query)
                message="📊 *VPS Real-time Traffic Status* ($VPS_NAME)
━━━━━━━━━━━━━━━━━━
• *Interface*: $INTERFACE
• *Today Download (RX)*: ${TODAY_RX_GB} GB
• *Today Upload (TX)*: ${TODAY_TX_GB} GB
• *Today Total Used*: *${TODAY_TOTAL_GB} GB*
• *Cycle Total Used*: *${USED_GB} GB* (of ${LIMIT_GB} GB)
• *Usage Ratio*: *${USED_PERCENT}%*
• *Billing Cycle*: Monthly day ${RESET_DAY}"
                ;;
        esac
    fi
    echo "$message"
}

# Handle manual test execution (reuses query card style)
if [ "$1" = "test" ] || [ "$1" = "--test" ]; then
    if [ "$MONITOR_LANG" = "zh" ]; then
        echo "正在向 Telegram 发送包含实时数据的测试通知..."
    else
        echo "Sending test Telegram notification with real statistics..."
    fi
    TEST_MESSAGE=$(generate_message "query")
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
    if ! [[ "$LAST_STAGE" =~ ^[0-9]+$ ]]; then
        LAST_STAGE=0
    fi
fi

# Trigger notifications if we moved to a higher alert stage
if [ "$CURRENT_STAGE" -gt "$LAST_STAGE" ]; then
    MESSAGE=$(generate_message "alert" "$CURRENT_STAGE")
    send_tg_notification "$MESSAGE"
fi

# Try to load last billing month recorded to detect billing cycle transitions
LAST_BILL_MONTH=""
if [ -f "$MONTH_STATE_FILE" ]; then
    LAST_BILL_MONTH=$(cat "$MONTH_STATE_FILE")
fi

# Reset state when a new billing cycle month transition is detected
if [ -n "$LAST_BILL_MONTH" ] && [ "$LAST_BILL_MONTH" != "$CURRENT_BILL_MONTH" ]; then
    RESET_MESSAGE=$(generate_message "reset")
    send_tg_notification "$RESET_MESSAGE"

    # Reset alert level status to prevent carrying over old stage thresholds
    CURRENT_STAGE=0
fi

# Persist state parameters
echo "$CURRENT_STAGE" > "$ALERT_STATE_FILE"
echo "$CURRENT_BILL_MONTH" > "$MONTH_STATE_FILE"

# Daily Report Summary Logic
if [ "$DAILY_REPORT" = "true" ]; then
    CURRENT_HOUR=$(date '+%H')
    CURRENT_DATE=$(date '+%Y-%m-%d')
    CURRENT_HOUR_INT=$((10#$CURRENT_HOUR))
    TARGET_HOUR_INT=$((10#$DAILY_REPORT_HOUR))

    if [ "$CURRENT_HOUR_INT" -eq "$TARGET_HOUR_INT" ]; then
        LAST_DAILY_DATE=""
        if [ -f "$DAILY_STATE_FILE" ]; then
            LAST_DAILY_DATE=$(cat "$DAILY_STATE_FILE")
        fi

        if [ "$LAST_DAILY_DATE" != "$CURRENT_DATE" ]; then
            DAILY_MESSAGE=$(generate_message "daily")
            send_tg_notification "$DAILY_MESSAGE"
            echo "$CURRENT_DATE" > "$DAILY_STATE_FILE"
        fi
    fi
fi
