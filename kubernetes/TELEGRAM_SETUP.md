# Kubernetes Health Checker - Telegram Setup Guide

## Quick Start for Telegram Integration

This guide helps you set up Telegram notifications for the Kubernetes health checker.

## Step 1: Create a Telegram Bot

### Using BotFather
1. Open Telegram mobile app or web version
2. Search for `@BotFather` (official Telegram bot creator)
3. Start a chat with BotFather
4. Send `/newbot` command
5. Choose a name for your bot (e.g., "K8s Health Bot")
6. Choose a username for your bot (e.g., "k8s_health_bot")
7. BotFather will give you a **Bot Token**

### Example Bot Token
```
1234567890:ABCdefGHIjklmnoPQRstuvwxyzABCDEFGHI
```

## Step 2: Get Your Chat ID

### Method 1: Using the Bot
1. Start a chat with your newly created bot
2. Send any message (e.g., "Hello")
3. Go to: `https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates`
4. Replace `<YOUR_BOT_TOKEN>` with your actual token
5. Look for `"chat"` → `"id"` in the JSON response

### Example Response
```json
{
  "ok": true,
  "result": [
    {
      "update_id": 123456789,
      "message": {
        "message_id": 1,
        "from": {
          "id": 987654321,
          "is_bot": false,
          "first_name": "Your Name"
        },
        "chat": {
          "id": 987654321,
          "first_name": "Your Name",
          "type": "private"
        },
        "text": "Hello"
      }
    }
  ]
}
```

**Your Chat ID is: `987654321`**

## Step 3: Configure the Health Checker Script

### Create Configuration File

```bash
sudo mkdir -p /etc/system_scripts
sudo nano /etc/system_scripts/auth.conf
```

### Add These Lines

```bash
# Telegram Bot Configuration for Kubernetes Health Checker
TELEGRAM_BOT_TOKEN="1234567890:ABCdefGHIjklmnoPQRstuvwxyzABCDEFGHI"
TELEGRAM_CHAT_ID="987654321"
```

### Secure the Configuration

```bash
sudo chmod 600 /etc/system_scripts/auth.conf
sudo chown root:root /etc/system_scripts/auth.conf
```

## Step 4: Test the Setup

### Test Telegram Connection

```bash
# Test with curl directly
curl -X POST https://api.telegram.org/bot<YOUR_BOT_TOKEN>/sendMessage \
  -d "chat_id=<YOUR_CHAT_ID>" \
  -d "text=Test message from Kubernetes Health Checker" \
  -d "parse_mode=HTML"
```

### Run Health Checker

```bash
./kubernetes_health_checker.sh
```

You should receive a Telegram notification with the health report.

## Step 5: Set Up Automated Monitoring

### Option 1: Cron Job (Every Hour)

```bash
# Edit crontab
crontab -e

# Add this line to run health check every hour
0 * * * * /path/to/kubernetes_health_checker.sh > /tmp/k8s_health.log 2>&1
```

### Option 2: Cron Job (Multiple Times Daily)

```bash
# Run every 6 hours
0 */6 * * * /path/to/kubernetes_health_checker.sh > /tmp/k8s_health.log 2>&1

# Run every 2 hours
0 */2 * * * /path/to/kubernetes_health_checker.sh > /tmp/k8s_health.log 2>&1

# Run every 30 minutes
*/30 * * * * /path/to/kubernetes_health_checker.sh > /tmp/k8s_health.log 2>&1
```

### Option 3: SystemD Timer (Recommended)

Create `/etc/systemd/system/k8s-health-check.service`:

```ini
[Unit]
Description=Kubernetes Health Checker
After=network.target

[Service]
Type=oneshot
ExecStart=/path/to/kubernetes_health_checker.sh
StandardOutput=journal
StandardError=journal
```

Create `/etc/systemd/system/k8s-health-check.timer`:

```ini
[Unit]
Description=Run Kubernetes Health Checker Every Hour
Requires=k8s-health-check.service

[Timer]
OnBootSec=5min
OnUnitActiveSec=1h
Persistent=true

[Install]
WantedBy=timers.target
```

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable k8s-health-check.timer
sudo systemctl start k8s-health-check.timer

# Check status
sudo systemctl status k8s-health-check.timer
```

## Telegram Notification Formats

### Healthy Cluster
```
✅ Kubernetes Health Report
Status: HEALTHY
Score: 95/100
Cluster: production

Nodes: 5/5 Ready
Pods: 150/150 Running

Time: 2026-04-11 10:30:45 UTC
```

### Warning State
```
⚠️ Kubernetes Health Report
Status: WARNING
Score: 75/100
Cluster: production

Nodes: 4/5 Ready
Pods: 145/150 Running

⚠️ WARNINGS (2):
• 1 node(s) not ready
• Pod kube-system/dns is pending

Time: 2026-04-11 10:30:45 UTC
```

### Critical State
```
🚨 Kubernetes Health Report
Status: CRITICAL
Score: 40/100
Cluster: production

Nodes: 2/5 Ready
Pods: 100/150 Running

🚨 ALERTS (3):
• Node worker-3 is not ready
• Pod default/app-1 has 15 restarts
• Control plane degraded

⚠️ WARNINGS (2):
• 2 node(s) not ready
• Multiple pod failures

Time: 2026-04-11 10:30:45 UTC
```

## Troubleshooting

### Test if Telegram works
```bash
# Verify credentials
cat /etc/system_scripts/auth.conf

# Test directly
curl -X POST https://api.telegram.org/bot<TOKEN>/sendMessage \
  -d "chat_id=<CHAT_ID>" \
  -d "text=Hello+from+K8s+Health+Checker" \
  -d "parse_mode=HTML"
```

### Common Errors

| Error | Solution |
|-------|----------|
| "Invalid bot token" | Check token format and regenerate from BotFather |
| "Chat not found" | Verify chat ID, make sure you started bot chat |
| "Unauthorized" | Ensure bot hasn't been blocked, restart bot in BotFather |
| "Telegram configuration not found" | Create `/etc/system_scripts/auth.conf` |

## Creating a Telegram Group for Notifications

### Setup Group Notifications

1. Create a new Telegram group
2. Add your bot to the group
3. Send a message in the group
4. Get the group chat ID:
   ```bash
   curl https://api.telegram.org/bot<TOKEN>/getUpdates
   ```
5. Look for a group message with negative chat ID (e.g., `-1001234567890`)
6. Use that ID in auth.conf

### Example Group Configuration
```bash
# For individual notifications
TELEGRAM_CHAT_ID="987654321"

# For group notifications
TELEGRAM_CHAT_ID="-1001234567890"
```

## Security Notes

1. **Keep Bot Token Secret** - Treat like a password
2. **Restrict File Permissions** - `chmod 600` on auth.conf
3. **Use Private Chats** - Prefer direct messages over groups for sensitive info
4. **Monitor Bot Activity** - Check BotFather for unauthorized access
5. **Rotate Tokens** - Consider regenerating tokens periodically

## Integration with Other Services

### Send to Multiple Channels
Create wrapper script:

```bash
#!/bin/bash
# Send to multiple chat IDs
TOKENS=("token1" "token2")
CHATS=("chat1" "chat2")

for i in "${!TOKENS[@]}"; do
    TELEGRAM_BOT_TOKEN="${TOKENS[$i]}"
    TELEGRAM_CHAT_ID="${CHATS[$i]}"
    /path/to/kubernetes_health_checker.sh
done
```

### Slack Integration (Alternative)
If you prefer Slack:

```bash
# Add to health checker script
curl -X POST -H 'Content-type: application/json' \
    --data '{"text":"K8s Health Report: ..."}' \
    $SLACK_WEBHOOK_URL
```

