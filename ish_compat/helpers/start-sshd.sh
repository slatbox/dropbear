#!/bin/sh
# Start (or report) the dropbear-ish SSH server on iSH / Minis.
#
# iSH leaks bound TCP ports after a server process dies, so we persist the
# last used port and walk upward until bind() succeeds.
#
# Install as /usr/local/bin/start-sshd (chmod +x).
# Replace <GATEWAY> below with your LAN default gateway (e.g. 192.168.31.1).

BIN=/usr/local/sbin/dropbear-ish
PORTFILE=/var/run/ssh.port
LOGFILE=/var/log/dropbear.log
LAST=$(cat "$PORTFILE" 2>/dev/null || echo 2241)

if pgrep -f 'sbin/dropbear-ish -E' > /dev/null 2>&1; then
    echo "dropbear-ish already running: PID $(pgrep -f 'sbin/dropbear-ish -E' | head -1)"
    PORT=$LAST
else
    PORT=$LAST
    until setsid "$BIN" -E -p "$PORT" > "$LOGFILE" 2>&1 < /dev/null & sleep 1; \
          pgrep -f 'sbin/dropbear-ish -E' > /dev/null 2>&1; do
        PORT=$((PORT + 1))
        [ "$PORT" -gt 2299 ] && { echo "no free port in 2242-2299"; exit 1; }
    done
    echo "$PORT" > "$PORTFILE"
    echo "dropbear-ish started (port $PORT)"
fi

# Detect the LAN IP. Proxy apps (Surge/Clash/...) hijack traffic to public
# IPs and return a fake-IP address (198.18.0.0/15), so prefer probing the
# default gateway and validate the result.
IP=$(timeout 8 python3 << 'PYEOF' 2>/dev/null
import socket

def probe(target):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(3)
    try:
        s.connect(target)
        return s.getsockname()[0]
    except Exception:
        return None
    finally:
        s.close()

def ok(ip):
    if not ip:
        return False
    parts = ip.split('.')
    if len(parts) != 4:
        return False
    a, b = int(parts[0]), int(parts[1])
    if a == 198 and b in (18, 19):      # proxy fake-IP range
        return False
    if a in (0, 127, 169):              # loopback / link-local
        return False
    if a == 192 and b == 168:
        return True
    if a == 10:
        return True
    if a == 172 and 16 <= b <= 31:
        return True
    return False

# Try the default gateway first (proxies usually bypass the local subnet),
# then a public address, then fall back to the cached value.
for target in [('<GATEWAY>', 53), ('8.8.8.8', 80)]:
    ip = probe(target)
    if ok(ip):
        print(ip)
        break
else:
    try:
        print(open('/var/run/ssh.ip').read().strip())
    except Exception:
        print('<LAN-IP>')
PYEOF
)
[ -n "$IP" ] && [ "$IP" != "<LAN-IP>" ] && echo "$IP" > /var/run/ssh.ip
echo "connect: ssh root@${IP:-<LAN-IP>} -p $PORT"
