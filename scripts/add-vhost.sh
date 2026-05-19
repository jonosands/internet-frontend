#!/usr/bin/env bash
# Scaffold a new vhost config file from the template.
# Usage: ./scripts/add-vhost.sh <hostname> <backend-address:port>
# Example: ./scripts/add-vhost.sh crm.example.com 192.168.1.20:443

set -euo pipefail

HOSTNAME="${1:?Usage: $0 <hostname> <backend>}"
BACKEND="${2:?Usage: $0 <hostname> <backend>}"
CONF="./nginx/conf.d/${HOSTNAME}.conf"

if [[ -f "${CONF}" ]]; then
  echo "Config already exists: ${CONF}" >&2
  exit 1
fi

cat > "${CONF}" <<EOF
# ---------------------------------------------------------------
# ${HOSTNAME}  →  https://${BACKEND}
# ---------------------------------------------------------------

server {
    listen 443 ssl;
    http2  on;
    server_name ${HOSTNAME};

    ssl_certificate     /etc/nginx/certs/${HOSTNAME}/fullchain.pem;
    ssl_certificate_key /etc/nginx/certs/${HOSTNAME}/privkey.pem;
    include /etc/nginx/snippets/ssl-params.conf;

    location / {
        include /etc/nginx/snippets/proxy-params.conf;
        proxy_pass https://${BACKEND};
    }
}
EOF

echo "Created: ${CONF}"
echo "Next steps:"
echo "  1. Add a cert:   ./scripts/gen-self-signed.sh ${HOSTNAME}"
echo "                or ./scripts/gen-letsencrypt.sh ${HOSTNAME} you@example.com"
echo "                or ./scripts/install-cert.sh ${HOSTNAME} /path/fullchain.pem /path/privkey.pem"
echo "  2. Reload nginx: docker compose exec nginx nginx -s reload"
