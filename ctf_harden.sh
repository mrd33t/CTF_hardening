#!/bin/bash
# ===========================
# Linux CTF Quick Harden (WITH Password Logging)
# ===========================

if [ "$EUID" -ne 0 ]; then
  echo "Run as root!"
  exit 1
fi

PWFILE="/root/ctf_pw_reset.txt"
echo "" > $PWFILE   # Clear previous

echo "[*] Updating system..."
DEBIAN_FRONTEND=noninteractive apt-get update -qq && apt-get upgrade -y -qq

echo "[*] Resetting passwords for local users..."
for user in $(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd); do
    pw=$(openssl rand -base64 16)
    echo "$user:$pw" | chpasswd
    echo "$user:$pw" >> $PWFILE
done

echo "[*] Locking guest and unnecessary system accounts..."
for sys in guest nobody sync; do
    if id $sys &>/dev/null; then
        usermod -L $sys
        echo "$sys: LOCKED" >> $PWFILE
    fi
done

echo "[*] Installing and enabling UFW firewall..."
apt-get install -y ufw
ufw default deny incoming
ufw default allow outgoing
# ufw allow ssh   # comment this if ssh is NOT needed!
ufw --force enable

echo "[*] Disabling dangerous services..."
disable_list="telnetd rsh-server rlogin-server rexec-server xinetd tftp tftpd"
for svc in $disable_list; do
    systemctl stop $svc 2>/dev/null
    systemctl disable $svc 2>/dev/null
done

echo "[*] Hardening SSHD configuration..."
sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i '/^#PasswordAuthentication/c\PasswordAuthentication yes' /etc/ssh/sshd_config
systemctl reload sshd

echo "[*] Enabling auditd for system logging..."
apt-get install -y auditd
systemctl enable --now auditd

echo ""
echo "==> New local user passwords are written to $PWFILE <=="
echo "Linux CTF Baseline Hardening Applied!"
