#!/bin/bash

# Configuration
ENV_FILE="$(dirname "$0")/telegram.env"

if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
else
    echo "Error: $ENV_FILE not found."
    exit 1
fi

if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ] || [ "$TELEGRAM_BOT_TOKEN" = "YOUR_BOT_TOKEN_HERE" ]; then
    echo "Telegram credentials not configured in $ENV_FILE."
    exit 1
fi

MESSAGE="$1"

if [ -z "$MESSAGE" ]; then
    echo "Usage: $0 \"Message to send\""
    exit 1
fi

curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="${TELEGRAM_CHAT_ID}" \
    -d parse_mode="Markdown" \
    -d text="${MESSAGE}" > /dev/null
