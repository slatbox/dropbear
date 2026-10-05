#!/bin/sh
# Restart the dropbear-ish SSH server on iSH / Minis.
#
# Kills any running instance, starts a fresh one on a free port (iSH keeps
# old ports stuck in "Address in use"), and prints the connection info.
#
# Install as /usr/local/bin/restart-sshd (chmod +x).

pkill -f 'sbin/dropbear-ish -E'
sleep 1

PORT=$(cat /var/run/ssh.port 2>/dev/null || echo 2242)
until setsid /usr/local/sbin/dropbear-ish -E -p "$PORT" \
        > /var/log/dropbear.log 2>&1 < /dev/null & sleep 1; \
      pgrep -f 'sbin/dropbear-ish -E' > /dev/null 2>&1; do
    PORT=$((PORT + 1))
    [ "$PORT" -gt 2299 ] && { echo "no free port in 2242-2299"; exit 1; }
done
echo "$PORT" > /var/run/ssh.port

echo ""
echo "===== SSH service restarted ====="
start-sshd
