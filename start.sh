#!/bin/sh

: "${UUID:?UUID is required}"
export DOMAIN="${DOMAIN:-$RAILWAY_PUBLIC_DOMAIN}"
: "${DOMAIN:?DOMAIN is required}"
export PORT="${PORT:-8080}"
export WS_PATH="${WS_PATH:-/ws}"
export XH_PATH="${XH_PATH:-/xh}"
export SUB_PATH="${SUB_PATH:-/sub}"
NAME="${NAME_PREFIX:-node}"
LOGLVL="${XRAY_LOG:-warning}"

enc() { printf %s "$1" | sed 's#/#%2F#g'; }

P_V="${WS_PATH}v"; P_M="${WS_PATH}m"; P_T="${WS_PATH}t"

L1="vless://${UUID}@${DOMAIN}:443?encryption=none&security=tls&sni=${DOMAIN}&type=ws&host=${DOMAIN}&path=$(enc "$P_V")#${NAME}-VLESS-WS"

VM=$(printf '{"v":"2","ps":"%s-VMess-WS","add":"%s","port":"443","id":"%s","aid":"0","scy":"auto","net":"ws","type":"none","host":"%s","path":"%s","tls":"tls","sni":"%s"}' "$NAME" "$DOMAIN" "$UUID" "$DOMAIN" "$P_M" "$DOMAIN" | base64 -w0)
L2="vmess://${VM}"

L3="trojan://${UUID}@${DOMAIN}:443?security=tls&sni=${DOMAIN}&type=ws&host=${DOMAIN}&path=$(enc "$P_T")#${NAME}-Trojan-WS"

L4="vless://${UUID}@${DOMAIN}:443?encryption=none&security=tls&sni=${DOMAIN}&type=xhttp&host=${DOMAIN}&path=$(enc "$XH_PATH")&mode=packet-up#${NAME}-VLESS-XHTTP"

export SUB_B64=$(printf '%s\n%s\n%s\n%s\n' "$L1" "$L2" "$L3" "$L4" | base64 -w0)

cat > /tmp/x.json <<EOF
{
"log": {"loglevel": "${LOGLVL}"},
"dns": {"servers": ["1.1.1.1", "8.8.8.8"], "queryStrategy": "UseIPv4"},
"inbounds": [
{"listen": "127.0.0.1", "port": 10001, "protocol": "vless",
"settings": {"clients": [{"id": "${UUID}"}], "decryption": "none"},
"streamSettings": {"network": "ws", "wsSettings": {"path": "${P_V}"}}},
{"listen": "127.0.0.1", "port": 10002, "protocol": "vmess",
"settings": {"clients": [{"id": "${UUID}"}]},
"streamSettings": {"network": "ws", "wsSettings": {"path": "${P_M}"}}},
{"listen": "127.0.0.1", "port": 10003, "protocol": "trojan",
"settings": {"clients": [{"password": "${UUID}"}]},
"streamSettings": {"network": "ws", "wsSettings": {"path": "${P_T}"}}},
{"listen": "127.0.0.1", "port": 10004, "protocol": "vless",
"settings": {"clients": [{"id": "${UUID}"}], "decryption": "none"},
"streamSettings": {"network": "xhttp", "xhttpSettings": {"path": "${XH_PATH}", "mode": "auto"}}}
],
"outbounds": [{"protocol": "freedom", "settings": {"domainStrategy": "UseIPv4"}}]
}
EOF

xray run -test -c /tmp/x.json || { echo "xray config invalid"; exit 1; }

( xray run -c /tmp/x.json; echo "xray exited"; kill 1 ) &

exec caddy run --config "${CADDYFILE:-/etc/caddy/Caddyfile}" --adapter caddyfile
