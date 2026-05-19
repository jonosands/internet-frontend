#!/usr/bin/env bash
# Obtain a Let's Encrypt certificate for a hostname using the webroot method.
# The nginx container must be running (to serve the ACME challenge on port 80).
# Usage: ./scripts/gen-letsencrypt.sh <hostname> <email>
# Example: ./scripts/gen-letsencrypt.sh app1.example.com admin@example.com

set -euo pipefail

HOSTNAME="${1:?Usage: $0 <hostname> <email>}"
EMAIL="${2:?Usage: $0 <hostname> <email>}"

# Certbot writes certs into ./certs/live/<hostname>/
docker compose run --rm certbot certbot certonly \
  --webroot \
  --webroot-path /var/www/certbot \
  --email "${EMAIL}" \
  --agree-tos \
  --no-eff-email \
  --domains "${HOSTNAME}" \
  --cert-path /etc/letsencrypt/live/${HOSTNAME}/fullchain.pem \
  --key-path  /etc/letsencrypt/live/${HOSTNAME}/privkey.pem

echo ""
echo "Certificate issued. Update nginx conf to point at:"
echo "  /etc/nginx/certs/live/${HOSTNAME}/fullchain.pem"
echo "  /etc/nginx/certs/live/${HOSTNAME}/privkey.pem"
echo ""
echo "Then reload nginx:"
echo "  docker compose exec nginx nginx -s reload"
