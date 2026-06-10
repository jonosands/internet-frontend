# internet-frontend

nginx reverse proxy that terminates HTTPS from clients and re-encrypts to internal backend servers (SSL bridging).

## Structure

```
internet-frontend/
├── Dockerfile                # nginx:stable-alpine + compiled GeoIP2 module
├── docker-compose.yml
├── .env.example              # MaxMind credentials template (copy to .env)
├── nginx/
│   ├── nginx.conf            # Main config; GeoIP2 lookups + allowlist maps
│   ├── conf.d/               # One .conf file per vhost
│   └── snippets/
│       ├── ssl-params.conf       # TLS settings (shared)
│       ├── proxy-params.conf     # Proxy headers + SSL re-encrypt settings
│       └── geo-allowlist.conf    # NZ/AU + Starlink filter (included per vhost)
├── geoip/                    # GeoLite2 .mmdb files — never committed (licensed)
├── certs/                    # Certs go here — never committed to git
│   └── <hostname>/
│       ├── fullchain.pem
│       └── privkey.pem
└── scripts/
    ├── add-vhost.sh          # Scaffold a new vhost config
    ├── gen-self-signed.sh    # Generate self-signed cert
    ├── gen-letsencrypt.sh    # Obtain Let's Encrypt cert
    ├── install-cert.sh       # Copy existing cert into place
    └── update-geoip.sh       # Download/refresh GeoLite2 databases
```

## Quick start

```bash
# Make scripts executable
chmod +x scripts/*.sh

# Add a vhost (creates nginx/conf.d/<hostname>.conf)
./scripts/add-vhost.sh myapp.example.com 192.168.1.10:443

# Add a certificate (choose one):
./scripts/gen-self-signed.sh myapp.example.com
./scripts/gen-letsencrypt.sh myapp.example.com admin@example.com
./scripts/install-cert.sh myapp.example.com /path/to/fullchain.pem /path/to/privkey.pem

# Put MaxMind credentials in .env (see GeoIP2 allowlist section below). The
# geoipupdate service downloads the databases on first start and refreshes them
# on a schedule; nginx waits for them via a healthcheck (fail-closed).
cp .env.example .env && $EDITOR .env

# Build the image (compiles the GeoIP2 module) and start the stack
docker compose up -d --build

# Test nginx config before reloading
docker compose exec nginx nginx -t

# Reload nginx after changes
docker compose exec nginx nginx -s reload
```

## Let's Encrypt auto-renewal

Start the certbot sidecar alongside nginx:

```bash
docker compose --profile letsencrypt up -d
```

Certbot will attempt renewal every 12 hours. Certificates are stored in `./certs/live/<hostname>/`.

## Adding a new backend

1. Run `./scripts/add-vhost.sh <hostname> <backend-ip:port>`
2. Add a cert for that hostname
3. Reload nginx

## Blackholing and logging

### Philosophy

Vhosts use nginx's `return 444` (connection close, no response) to drop traffic that has no legitimate reason to reach the backend. The goal is to protect backends from scanner noise and accidental exposure of paths that should never be reachable through this proxy.

Two patterns are used depending on how locked-down the vhost needs to be:

**Explicit extension block** (used by hf.ignition.net.nz): Allow all paths through except known scanner bait — `.php`, `.asp`, `.aspx`, `.cgi`, `.env`, `.git`. These extensions are never served by the backend and only appear in automated scans. Everything else proxies normally.

```nginx
location ~* \.(php|asp|aspx|cgi|env|git)$ {
    access_log /var/log/nginx-custom/hf-blackhole.log blackhole;
    return 444;
}
```

**Default-deny catch-all** (used by ice and landsar): Explicitly whitelist every legitimate path, then blackhole the default `location /` block. Anything not in the whitelist is dropped. This is appropriate for backends with a small, well-defined URL surface (e.g. a Flutter SPA with a fixed set of entry points).

```nginx
location / {
    access_log /var/log/nginx-custom/ice-blackhole.log blackhole;
    return 444;
}
```

### Log format

A dedicated `blackhole` log format is defined in `nginx.conf` and written to `/var/log/nginx-custom/<vhost>-blackhole.log`. It captures IP, timestamp, request line, User-Agent, Referer, and Origin — enough to identify scanner campaigns and see whether anything legitimate is getting caught.

```
$remote_addr [$time_local] "$request" ua="$http_user_agent" ref="$http_referer" origin="$http_origin"
```

The main access log uses the `main` format (which also includes `upstream` and `host`) and goes to the standard nginx log inside the container.

### Discovery workflow

When adding a new vhost or tightening an existing one, use the access logs to observe before blocking:

1. Deploy the vhost with `return 444` in place but watch the blackhole log: `docker compose exec nginx tail -f /var/log/nginx-custom/<vhost>-blackhole.log`
2. If legitimate traffic appears there, add an explicit `location` block for that path above the blackhole rule.
3. Once the blackhole log is quiet for normal usage, the rule is correctly scoped.

The inline comment `# Swap return 444 for proxy_pass during discovery to observe before blocking` in vhost configs marks where this swap should happen.

## GeoIP2 allowlist (NZ / AU + Starlink)

Every vhost is locked to a **whitelist**: a connection is allowed only if its
source IP is

1. geolocated to **NZ** or **AU** (MaxMind GeoLite2-Country), **or**
2. on a **Starlink / SpaceX ASN** (GeoLite2-ASN) — allowed worldwide, **or**
3. an **internal / trusted network** (loopback + RFC1918), so health checks,
   LAN clients and backends are never caught.

Anything else is dropped with `return 444` — a silent connection close that
sends no response, so the filter is invisible to the client (it looks like the
site simply isn't there). The raw TCP passthrough on `:7443` (stream) enforces
the same rule by routing blocked connections to an empty upstream, which closes
them without a reply.

### How it works

- The GeoIP2 module is **compiled into the image** (`Dockerfile`) — the stock
  `nginx:stable-alpine` doesn't ship it. The build derives the nginx version
  from the base image so a `docker compose build --pull` always produces a
  binary-compatible module.
- `nginx/nginx.conf` defines the `geoip2{}` lookups (`$remote_addr` → country
  ISO + ASN), an internal-network `geo{}` block, and `map`s that combine them
  into `$geo_blocked` / `$log_offshore_starlink`. Source is **`$remote_addr`**
  (the real TCP peer) — never `X-Forwarded-For`, which a client can spoof.
- `nginx/snippets/geo-allowlist.conf` is included in each vhost; it does the
  `return 444` and the conditional logging.

### Starlink ASNs

Keyed on ASN (stable), not org name. `14593` (SPACEX-STARLINK) is the primary
consumer egress; `397763`, `149662`, `53348` are SpaceX-owned members of the
same as-set that carry a small tail of traffic. Edit the `$geo_is_starlink` /
`$stream_is_starlink` maps in `nginx.conf` to adjust.

### Databases

GeoLite2 is free but requires a (free) MaxMind account. Put credentials in
`.env` (git-ignored):

```bash
cp .env.example .env   # then fill in MAXMIND_ACCOUNT_ID + MAXMIND_LICENSE_KEY
```

Refresh happens automatically — the **`geoipupdate` service** in
`docker-compose.yml` (official `ghcr.io/maxmind/geoipupdate` image) downloads
`GeoLite2-Country.mmdb` + `GeoLite2-ASN.mmdb` into the shared `geoip/` volume on
start, then re-checks every `GEOIPUPDATE_FREQUENCY` hours (default 24). It uses
the same `MAXMIND_*` vars from `.env`.

- **Self-bootstrapping:** the `geoipupdate` service has a healthcheck that goes
  green once both `.mmdb` files exist, and nginx `depends_on` it
  (`condition: service_healthy`) — so `docker compose up -d --build` downloads
  the databases first, then starts nginx. No manual pre-step needed.
- **Fail-closed:** nginx refuses to start without the `.mmdb` files. If the
  credentials are wrong, `geoipupdate` logs an auth error, never becomes
  healthy, and nginx stays down rather than serving without a filter. Check with
  `docker compose logs geoipupdate`.
- **Fresh-reload:** the **`geoip-reload` sidecar** (`scripts/geoip-reload-watch.sh`)
  SIGHUPs nginx the moment `geoipupdate` swaps the databases. Without it, nginx's
  `auto_reload 60m` leaves an up-to-60-min window where it can serve stale geo
  data (`country=ZZ`) and `444` legitimate NZ/AU users — which the browser shows
  as `ERR_HTTP2_PROTOCOL_ERROR`. The sidecar comes up with the stack; nothing to
  install. Check with `docker compose logs geoip-reload`.
- `geoip2{}` uses `auto_reload 60m;`, so a refreshed database is picked up within
  an hour with no nginx reload. The updater is a no-op when nothing is new, so a
  daily cadence won't burn the GeoLite download quota.
- The `.mmdb` files are **never committed** (`geoip/.gitignore`) — MaxMind's
  licence forbids redistribution and they go stale fast.
- **Manual alternative:** `./scripts/update-geoip.sh` fetches the same databases
  directly (with sha256 verification) — useful for a one-off refresh or a
  non-Docker host. The `geoipupdate` service is the primary mechanism.

### Logs (under `./logs`, i.e. `/var/log/nginx-custom`)

| File | What |
|------|------|
| `geo-block.log` | Every blocked request (`geo_audit` format: IP, country, ASN, org, host, request, status, UA). The client only sees a closed connection; this is server-side for tuning. |
| `offshore-starlink.log` | Starlink connections originating **outside** NZ/AU — allowed, but recorded for visibility. |
| `stream-7443.log` | Every stream connection, now annotated with `country=`, `asn=`, `blocked=`, `offshore_starlink=`. |

### Accuracy caveats

GeoIP is approximate and a hard `444` will occasionally misjudge at the margin.
Starlink is the notable case: traffic egresses at a ground-station POP, not the
dish, so a Starlink IP can geolocate to a neighbouring/distant country, and
MaxMind is often stale for Starlink's fast-churning prefixes. That's exactly why
Starlink ASNs are allowlisted outright (rather than relying on their country)
and why offshore Starlink is logged rather than blocked. If a CDN/load-balancer
is ever placed in front of this proxy, you **must** add the `realip` module with
that provider's CIDRs in `set_real_ip_from` before the geo source is correct —
otherwise every client appears to come from the fronting proxy.

## SSL bridging notes

- nginx terminates the client TLS connection using certs in `certs/<hostname>/`
- Outbound connections to backends use HTTPS
- Backend SSL verification is **disabled by default** (`proxy_ssl_verify off`) because internal backends often use self-signed certs
- To enable verification for a backend, set `proxy_ssl_verify on` and add `proxy_ssl_trusted_certificate /path/to/backend-ca.pem;` in the relevant vhost
