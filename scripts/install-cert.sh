#!/usr/bin/env bash
# Copy an existing certificate pair into the certs directory for a hostname.
# Usage: ./scripts/install-cert.sh <hostname> <path/to/fullchain.pem> <path/to/privkey.pem>

set -euo pipefail

HOSTNAME="${1:?Usage: $0 <hostname> <fullchain.pem> <privkey.pem>}"
FULLCHAIN="${2:?Usage: $0 <hostname> <fullchain.pem> <privkey.pem>}"
PRIVKEY="${3:?Usage: $0 <hostname> <fullchain.pem> <privkey.pem>}"

CERT_DIR="./certs/${HOSTNAME}"
mkdir -p "${CERT_DIR}"

cp "${FULLCHAIN}" "${CERT_DIR}/fullchain.pem"
cp "${PRIVKEY}"   "${CERT_DIR}/privkey.pem"
chmod 644 "${CERT_DIR}/fullchain.pem"
chmod 600 "${CERT_DIR}/privkey.pem"

echo "Certs installed to ${CERT_DIR}/"
echo "Reload nginx with:  docker compose exec nginx nginx -s reload"
