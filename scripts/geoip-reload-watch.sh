#!/bin/sh
# GeoIP reload watcher — runs in the `geoip-reload` sidecar, which shares the
# nginx container's PID namespace (pid: "service:nginx" in docker-compose.yml).
#
# nginx's geoip2 `auto_reload 60m` only re-checks the .mmdb files hourly, so for
# up to ~60 min after geoipupdate swaps the databases nginx can keep serving
# stale data (country=ZZ) and the geo-allowlist then 444s legitimate NZ/AU users
# — which browsers surface as ERR_HTTP2_PROTOCOL_ERROR. This watcher closes that
# window: it polls the Country DB mtime and, when it changes (i.e. right after
# geoipupdate's atomic rename completes), sends SIGHUP to the nginx master for a
# full, clean reload that re-opens the fresh databases immediately.
set -eu

WATCH="${GEOIP_WATCH_FILE:-/geoip/GeoLite2-Country.mmdb}"
INTERVAL="${GEOIP_RELOAD_INTERVAL:-30}"
last=""

echo "$(date -u +%FT%TZ) geoip-reload watching $WATCH (every ${INTERVAL}s)"
while true; do
  cur="$(stat -c %Y "$WATCH" 2>/dev/null || echo "")"
  if [ -n "$cur" ] && [ -n "$last" ] && [ "$cur" != "$last" ]; then
    # Lowest nginx PID = the master (started first); SIGHUP it to reload config.
    pid="$(pidof nginx 2>/dev/null | tr ' ' '\n' | sort -n | head -1)"
    if [ -n "$pid" ] && kill -HUP "$pid" 2>/dev/null; then
      echo "$(date -u +%FT%TZ) geoip mmdb changed -> SIGHUP nginx master (pid $pid)"
    else
      echo "$(date -u +%FT%TZ) geoip mmdb changed but no nginx master found to signal"
    fi
  fi
  last="$cur"
  sleep "$INTERVAL"
done
