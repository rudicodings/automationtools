#!/bin/bash
#
# AlmaLinux 9 - Enable Root SSH Password Login
#
# No password is stored in this file (safe for a public GitHub repo).
# The root password comes from the ROOT_PASS variable given in the command.
# If ROOT_PASS is not set, the script asks for it on the terminal.
#
# As a normal user with sudo:
#   sudo ROOT_PASS='YOUR_PASSWORD' bash -c "$(curl -fsSL URL)"
# As root:
#   ROOT_PASS='YOUR_PASSWORD' bash -c "$(curl -fsSL URL)"

set -e

echo "=========================================="
echo " AlmaLinux 9 - Enable Root SSH Password"
echo "=========================================="

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script needs root privileges."
    echo
    echo "You are logged in as a normal user. Run it with sudo:"
    echo "  sudo ROOT_PASS='YOUR_PASSWORD' bash -c \"\$(curl -fsSL URL)\""
    exit 1
fi

echo
echo "[1/7] Root password"
echo

if [ -n "${ROOT_PASS:-}" ]; then
    if [ "${#ROOT_PASS}" -lt 8 ]; then
        echo "ERROR: ROOT_PASS is too short (minimum 8 characters)."
        exit 1
    fi
    PASS1="$ROOT_PASS"
    echo "Using the password provided in ROOT_PASS."
else
    if [ ! -r /dev/tty ]; then
        echo "ERROR: ROOT_PASS is not set and no terminal is available."
        exit 1
    fi
    while true; do
        read -rs -p "Enter new root password: " PASS1 < /dev/tty
        echo
        read -rs -p "Confirm new root password: " PASS2 < /dev/tty
        echo

        if [ -z "$PASS1" ]; then
            echo "Password cannot be empty. Try again."
            echo
        elif [ "${#PASS1}" -lt 8 ]; then
            echo "Password is too short (minimum 8 characters). Try again."
            echo
        elif [ "$PASS1" != "$PASS2" ]; then
            echo "Passwords do not match. Try again."
            echo
        else
            break
        fi
    done
fi

echo
echo "[2/7] Installing required packages..."
dnf install -y openssh-server nano

echo
echo "[3/7] Backing up SSH configuration..."

BACKUP="/root/ssh-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"

cp -a /etc/ssh/sshd_config "$BACKUP/"

if [ -d /etc/ssh/sshd_config.d ]; then
    cp -a /etc/ssh/sshd_config.d "$BACKUP/"
fi

echo "Backup created: $BACKUP"

echo
echo "[4/7] Updating SSH configuration..."

# Main sshd_config
if grep -Eq '^[[:space:]]*#?[[:space:]]*PermitRootLogin[[:space:]]+' /etc/ssh/sshd_config; then
    sed -i -E 's/^[[:space:]]*#?[[:space:]]*PermitRootLogin[[:space:]]+.*/PermitRootLogin yes/' /etc/ssh/sshd_config
else
    echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
fi

if grep -Eq '^[[:space:]]*#?[[:space:]]*PasswordAuthentication[[:space:]]+' /etc/ssh/sshd_config; then
    sed -i -E 's/^[[:space:]]*#?[[:space:]]*PasswordAuthentication[[:space:]]+.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
else
    echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config
fi

# Update all existing SSH .conf files
if [ -d /etc/ssh/sshd_config.d ]; then

    for file in /etc/ssh/sshd_config.d/*.conf; do

        [ -f "$file" ] || continue

        echo "Checking: $file"

        if grep -Eq '^[[:space:]]*#?[[:space:]]*PermitRootLogin[[:space:]]+' "$file"; then
            sed -i -E 's/^[[:space:]]*#?[[:space:]]*PermitRootLogin[[:space:]]+.*/PermitRootLogin yes/' "$file"
        fi

        if grep -Eq '^[[:space:]]*#?[[:space:]]*PasswordAuthentication[[:space:]]+' "$file"; then
            sed -i -E 's/^[[:space:]]*#?[[:space:]]*PasswordAuthentication[[:space:]]+.*/PasswordAuthentication yes/' "$file"
        fi

    done

fi

# Create a final configuration file (99- loads last)
cat > /etc/ssh/sshd_config.d/99-root-password-login.conf <<'CONF'
PermitRootLogin yes
PasswordAuthentication yes
CONF

echo
echo "[5/7] Configuring cloud-init..."

if [ -f /etc/cloud/cloud.cfg ]; then

    if grep -Eq '^[[:space:]]*disable_root:' /etc/cloud/cloud.cfg; then
        sed -i -E 's/^[[:space:]]*disable_root:.*/disable_root: false/' /etc/cloud/cloud.cfg
    else
        echo "disable_root: false" >> /etc/cloud/cloud.cfg
    fi

    if grep -Eq '^[[:space:]]*ssh_pwauth:' /etc/cloud/cloud.cfg; then
        sed -i -E 's/^[[:space:]]*ssh_pwauth:.*/ssh_pwauth: true/' /etc/cloud/cloud.cfg
    else
        echo "ssh_pwauth: true" >> /etc/cloud/cloud.cfg
    fi

fi

echo
echo "[6/7] Setting root password..."
echo "root:${PASS1}" | chpasswd
unset PASS1 PASS2 ROOT_PASS
echo "Root password set."

echo
echo "[7/7] Testing SSH configuration..."

sshd -t

echo "SSH configuration test: OK"

echo
echo "Restarting SSH service..."

systemctl restart sshd

echo
echo "=========================================="
echo " Effective SSH Configuration"
echo "=========================================="

sshd -T | grep -Ei 'permitrootlogin|passwordauthentication|kbdinteractiveauthentication|usepam'

echo
echo "=========================================="
echo " SSH STATUS"
echo "=========================================="

systemctl --no-pager --full status sshd | head -20

SERVER_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"

echo
echo "=========================================="
echo " DONE"
echo "=========================================="

echo
echo "Now test from PuTTY:"
echo
echo "IP:       ${SERVER_IP:-YOUR_SERVER_IP}"
echo "Username: root"
echo "Password: (the password you provided)"
echo
echo "IMPORTANT: Keep this console open until"
echo "you successfully test the new SSH login."
echo
