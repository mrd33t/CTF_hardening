#!/bin/bash
# ============================# PvJ CTF Continuous Defense Script (Linux/Ubuntu)# ============================# Configurations
ALLOWED_SERVICES="ssh nginx apache2"
ALLOWED_PORTS="22 80 443"
ADMIN_GROUP="sudo"
HASHFILE="/root/sshd_config.loop.sha256"
CONFIG="/etc/ssh/sshd_config"
PWFILE="/root/ctf_pw_reset.txt"

# Email alert - requires 'mail' or 'sendmail' set up
EMAIL_ALERTS=false
EMAIL="yourteam@example.com"

send_alert() {
    MSG="$1"
    echo "$MSG"
    if $EMAIL_ALERTS; then
        echo "$MSG" | mail -s "PvJ CTF ALERT" "$EMAIL"
    fi
}

while true; do
    echo ""
    echo "[ $(date) ] Starting Blue Team Defense Cycle... "

    # 1. Patch Updates
    DEBIAN_FRONTEND=noninteractive apt-get update -yq && apt-get upgrade -yq

    # 2. UFW Firewall Enforce/Reset
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    for PORT in $ALLOWED_PORTS; do ufw allow $PORT; done
    ufw --force enable

    # 3. Service Audit
    RUNNING=$(systemctl list-units --type=service --state=running | awk '{print $1}' | grep '\.service$')
    for SVC in $RUNNING; do
        SHORT=$(echo "$SVC" | sed 's/\.service$//')
        if [[ ! " $ALLOWED_SERVICES " =~ " $SHORT " ]]; then
            send_alert "[!] Unapproved Linux service running: $SHORT"
            # Optionally: systemctl stop $SHORT
        fi
    done

    # 4. Listening Port Audit
    for PORT in $(ss -tuln | awk 'NR>1 {print $5}' | sed -E 's/.*:([0-9]+)$/\1/' | sort -u); do
        if [[ ! " $ALLOWED_PORTS " =~ " $PORT " ]]; then
            send_alert "[!] Unapproved port open: $PORT"
        fi
    done

    # 5. Account Audit (sudo/admin users)
    ADMINS=$(getent group $ADMIN_GROUP | cut -d: -f4 | tr ',' ' ')
    # Replace with a space-separated list of actual allowed team admin names
    ALLOWED_ADMINS="root ctfadmin"
    for USER in $ADMINS; do
        if [[ ! " $ALLOWED_ADMINS " =~ " $USER " ]]; then
            send_alert "[!] Unapproved sudo/admin detected: $USER"
        fi
    done

    # 6. Log Monitoring (SSH brute, new users, sudo usage)
    TAILLINES=30
    grep -Ei 'Failed password|Accepted password|useradd|sudo:' /var/log/auth.log | tail -$TAILLINES | while read -r LINE; do
        if echo "$LINE" | grep -q "Failed password"; then
            send_alert "[!] SSH brute force: $LINE"
        elif echo "$LINE" | grep -q "useradd"; then
            send_alert "[!] New user created: $LINE"
        elif echo "$LINE" | grep -q "sudo:"; then
            send_alert "[*] Sudo usage: $LINE"
        fi
    done

    # 7. Config File Integrity (sshd_config)
    if [ -f "$CONFIG" ]; then
        CUR_HASH=$(sha256sum "$CONFIG" | awk '{print $1}')
        if [ -f "$HASHFILE" ]; then
            LAST_HASH=$(cat "$HASHFILE")
            if [ "$CUR_HASH" != "$LAST_HASH" ]; then
                send_alert "[!] sshd_config file hash changed"
            fi
        fi
        echo "$CUR_HASH" > "$HASHFILE"
    fi

    # 8. Backup/Snapshot Reminder
    echo "[*] Consider a backup/snapshot now if stable."

    echo "[ $(date) ] Blue Team Loop Complete. Sleeping 15min..."
    sleep 900   # 15 minutes
done
