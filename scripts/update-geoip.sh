#!/usr/bin/env bash
#
# Download / refresh the MaxMind GeoLite2 Country + ASN databases into ./geoip/.
#
# GeoLite2 is free but requires a (free) MaxMind account — anonymous downloads
# were discontinued in 2019. Sign up at:
#   https://www.maxmind.com/en/geolite2/signup
# then create a licence key at:
#   https://www.maxmind.com/en/accounts/current/license-key
#
# Provide credentials via environment or a .env file in the repo root:
#   MAXMIND_ACCOUNT_ID=1234567
#   MAXMIND_LICENSE_KEY=xxxxxxxxxxxxxxxx
#
# Run before the first `docker compose up` (nginx fails closed without the DBs)
# and on a schedule thereafter (MaxMind refreshes Country twice weekly, ASN on
# weekdays). geoip2's `auto_reload 60m;` picks up new files without a reload.
#
# Usage:  ./scripts/update-geoip.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
GEOIP_DIR="$REPO_DIR/geoip"

# Load .env if present (without clobbering already-exported vars).
if [[ -f "$REPO_DIR/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$REPO_DIR/.env"
  set +a
fi

: "${MAXMIND_ACCOUNT_ID:?Set MAXMIND_ACCOUNT_ID (see https://www.maxmind.com/en/accounts/current/license-key)}"
: "${MAXMIND_LICENSE_KEY:?Set MAXMIND_LICENSE_KEY}"

mkdir -p "$GEOIP_DIR"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fetch() {
  local edition="$1"
  echo ">> Downloading ${edition} ..."
  # Auth is HTTP Basic (account id : licence key). -L follows the R2 redirect.
  curl -fSL --retry 3 -u "${MAXMIND_ACCOUNT_ID}:${MAXMIND_LICENSE_KEY}" \
    "https://download.maxmind.com/geoip/databases/${edition}/download?suffix=tar.gz" \
    -o "${tmp}/${edition}.tar.gz"

  # Verify against MaxMind's published sha256 for this build. Mandatory and
  # fail-closed: if the checksum can't be fetched we refuse to install rather
  # than trust an unverified file. (Keep `local want got` on its own line so a
  # curl/pipe failure propagates under `set -e`/pipefail.)
  local want got
  want="$(curl -fsSL --retry 3 -u "${MAXMIND_ACCOUNT_ID}:${MAXMIND_LICENSE_KEY}" \
    "https://download.maxmind.com/geoip/databases/${edition}/download?suffix=tar.gz.sha256" \
    | awk '{print $1}')"
  [[ -z "$want" ]] && { echo "ERROR: could not obtain SHA256 for ${edition}" >&2; exit 1; }
  got="$(sha256sum "${tmp}/${edition}.tar.gz" | awk '{print $1}')"
  if [[ "$want" != "$got" ]]; then
    echo "ERROR: checksum mismatch for ${edition} (want ${want}, got ${got})" >&2
    exit 1
  fi

  # Archive layout: <edition>_<date>/<edition>.mmdb
  tar -xzf "${tmp}/${edition}.tar.gz" -C "$tmp"
  local mmdb
  mmdb="$(find "$tmp" -name "${edition}.mmdb" | head -n1)"
  [[ -n "$mmdb" ]] || { echo "ERROR: ${edition}.mmdb not found in archive" >&2; exit 1; }

  # Atomic replace so nginx never sees a half-written file.
  install -m 0644 "$mmdb" "${GEOIP_DIR}/${edition}.mmdb.new"
  mv -f "${GEOIP_DIR}/${edition}.mmdb.new" "${GEOIP_DIR}/${edition}.mmdb"
  echo "   -> ${GEOIP_DIR}/${edition}.mmdb"
}

fetch GeoLite2-Country
fetch GeoLite2-ASN

echo
echo "Databases updated. If the container is running, nginx will auto_reload"
echo "them within 60m, or force it now:  docker compose exec nginx nginx -s reload"
