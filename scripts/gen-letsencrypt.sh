#!/usr/bin/env bash
# Obtain a Let's Encrypt certificate for a hostname using the webroot method.
# The nginx container must be running (to serve the ACME challenge on port 80).
#
# Usage:   ./scripts/gen-letsencrypt.sh <hostname> <email>
# Example: ./scripts/gen-letsencrypt.sh app1.example.com admin@example.com

set -euo pipefail

HOSTNAME="${1:?Usage: $0 <hostname> <email>}"
EMAIL="${2:?Usage: $0 <hostname> <email>}"

# Certbot writes certs into ./certs/live/<hostname>/
docker compose run --rm --no-deps certbot certonly \
  --webroot \
  --webroot-path /var/www/certbot \
  --email "${EMAIL}" \
  --agree-tos \
  --no-eff-email \
  --domains "${HOSTNAME}"

echo ""
echo "Certificate issued at: ./certs/live/${HOSTNAME}/"
echo ""
echo "For nginx vhosts, update conf to point at:"
echo "  /etc/nginx/certs/live/${HOSTNAME}/fullchain.pem"
echo "  /etc/nginx/certs/live/${HOSTNAME}/privkey.pem"
echo "Then reload: docker compose exec nginx nginx -s reload"
