#!/bin/sh
# Install dropbear-ish as a login SSH server on iSH / Minis.
#
# Run from a built checkout of the ish-compat branch after `make dropbear`.
# Installs:
#   /usr/local/sbin/dropbear-ish        server binary
#   /etc/dropbear/*_host_key            host keys (generated if missing)
#   /usr/local/bin/start-sshd           start helper
#   /usr/local/bin/restart-sshd         restart helper
#   /etc/profile.d/disable-mouse.sh     terminal mouse-mode reset on login
#
# Usage: install-sshd.sh [path-to-built-dropbear]   (default ./dropbear)
set -e

SRC=${1:-./dropbear}
[ -x "$SRC" ] || { echo "usage: $0 [path/to/dropbear]  (built binary)"; exit 1; }

mkdir -p /usr/local/sbin /usr/local/bin /etc/dropbear /etc/profile.d
install -m 755 "$SRC" /usr/local/sbin/dropbear-ish

# dropbearkey comes with the dropbear package.
for type in rsa ecdsa ed25519; do
    key=/etc/dropbear/dropbear_${type}_host_key
    [ -f "$key" ] || dropbearkey -t "$type" -f "$key" >/dev/null 2>&1 || true
done

here=$(cd "$(dirname "$0")" && pwd)
install -m 755 "$here/start-sshd.sh"     /usr/local/bin/start-sshd
install -m 755 "$here/restart-sshd.sh"   /usr/local/bin/restart-sshd
install -m 644 "$here/disable-mouse.sh"  /etc/profile.d/disable-mouse.sh

echo "Installed. Set a root password with:  echo 'root:YOURPASS' | chpasswd"
echo "Then start the server with:           start-sshd"
