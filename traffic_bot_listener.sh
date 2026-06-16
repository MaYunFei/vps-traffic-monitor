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
STATE_DIR=${STATE_DIR:-"/tmp"}
INTERFACE=${INTERFACE:-"default"}

# Offset state file to prevent duplicate message responses on service restart
OFFSET_FILE="${STATE_DIR}/vps_traffic_bot_offset_${INTERFACE}.state"

if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
    if [ "$MONITOR_LANG" = "zh" ]; then
        echo "错误: 未配置 TELEGRAM_BOT_TOKEN 或 TELEGRAM_CHAT_ID。" >&2
    else
        echo "Error: TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID is not configured." >&2
    fi
    exit 1
fi

# Load previous offset if exists
OFFSET=0
if [ -f "$OFFSET_FILE" ]; then
    OFFSET=$(cat "$OFFSET_FILE")
    if ! [[ "$OFFSET" =~ ^[0-9]+$ ]]; then
        OFFSET=0
    fi
fi

# Output daemon configurations based on selected language
if [ "$MONITOR_LANG" = "zh" ]; then
    echo "VPS 流量监听守护进程已启动..."
    echo "语言设置: 简体中文 | 授权 Chat ID: $TELEGRAM_CHAT_ID"
else
    echo "VPS Traffic Listener daemon started..."
    echo "Language: English | Authorized Chat ID: $TELEGRAM_CHAT_ID"
fi

while true; do
    # API query with long-polling timeout of 30s
    RESPONSE=$(curl -s --max-time 35 "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getUpdates?offset=${OFFSET}&limit=1&timeout=30")

    # Check if curl failed
    if [ $? -ne 0 ]; then
        # API check down or connection issue, sleep a bit before retrying
        sleep 5
        continue
    fi

    # Parse update outcome
    OK=$(echo "$RESPONSE" | jq -r '.ok' 2>/dev/null)
    if [ "$OK" != "true" ]; then
        sleep 5
        continue
    fi

    # Check if there is any update
    UPDATE_COUNT=$(echo "$RESPONSE" | jq '.result | length' 2>/dev/null)
    if [ "$UPDATE_COUNT" -eq 0 ] || [ -z "$UPDATE_COUNT" ]; then
        continue
    fi

    # Retrieve update details
    UPDATE_ID=$(echo "$RESPONSE" | jq '.result[0].update_id' 2>/dev/null)
    CHAT_ID=$(echo "$RESPONSE" | jq -r '.result[0].message.chat.id' 2>/dev/null)
    TEXT=$(echo "$RESPONSE" | jq -r '.result[0].message.text' 2>/dev/null)

    # Increment offset
    OFFSET=$((UPDATE_ID + 1))
    echo "$OFFSET" > "$OFFSET_FILE"

    # Only reply when chat_id matches the authorized config chat_id
    if [ "$CHAT_ID" = "$TELEGRAM_CHAT_ID" ]; then
        case "$TEXT" in
            /traffic|/status|/traffic@$(curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe" | jq -r '.result.username' 2>/dev/null))
                # Trigger real-time statistics message send
                bash "${SCRIPT_DIR}/traffic_monitor.sh" query "$CHAT_ID"
                ;;
            /start)
                # Welcome greeting
                if [ "$MONITOR_LANG" = "zh" ]; then
                    WELCOME="👋 *您好! 欢迎使用 VPS 流量监控助手*
━━━━━━━━━━━━━━━━━━
• 输入 /traffic 或 /status 能为您实时统计并查询当前网卡的上传、下载及已用流量消耗占比卡片。"
                else
                    WELCOME="👋 *Hello! Welcome to VPS Traffic Monitor Bot*
━━━━━━━━━━━━━━━━━━
• Use /traffic or /status to get real-time network traffic usage, downloads, uploads, and quota consumption cards."
                fi
                curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
                    -d "chat_id=${CHAT_ID}" \
                    -d "parse_mode=Markdown" \
                    -d "text=${WELCOME}" > /dev/null
                ;;
        esac
    elif [ "$CHAT_ID" != "null" ] && [ -n "$CHAT_ID" ]; then
        # Log unauthorized access attempts in service stdout
        echo "Unauthorized query blocked from Chat ID: $CHAT_ID with text: \"$TEXT\"" >&2

        # Send a tiny response to let the attacker know they can't access this bot
        UNAUTH_ERROR="⚠️ Access Denied / 访问被拒绝"
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
            -d "chat_id=${CHAT_ID}" \
            -d "text=${UNAUTH_ERROR}" > /dev/null
    fi
done
