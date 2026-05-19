#!/usr/bin/env bash
# Generate a self-signed certificate for a given hostname.
# Usage: ./scripts/gen-self-signed.sh <hostname>
# Example: ./scripts/gen-self-signed.sh app1.example.com

set -euo pipefail

HOSTNAME="${1:?Usage: $0 <hostname>}"
CERT_DIR="./certs/${HOSTNAME}"

mkdir -p "${CERT_DIR}"

openssl req -x509 -nodes -days 3650 \
  -newkey rsa:4096 \
  -keyout "${CERT_DIR}/privkey.pem" \
  -out    "${CERT_DIR}/fullchain.pem" \
  -subj   "/CN=${HOSTNAME}/O=Self-Signed/C=NZ" \
  -addext "subjectAltName=DNS:${HOSTNAME}"

chmod 600 "${CERT_DIR}/privkey.pem"
chmod 644 "${CERT_DIR}/fullchain.pem"

echo "Self-signed cert created: ${CERT_DIR}/"
echo "  fullchain.pem  (certificate)"
echo "  privkey.pem    (private key)"
