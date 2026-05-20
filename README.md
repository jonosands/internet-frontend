# internet-frontend

nginx reverse proxy that terminates HTTPS from clients and re-encrypts to internal backend servers (SSL bridging).

## Structure

```
internet-frontend/
├── docker-compose.yml
├── nginx/
│   ├── nginx.conf            # Main nginx config, HTTP→HTTPS redirect
│   ├── conf.d/               # One .conf file per vhost
│   └── snippets/
│       ├── ssl-params.conf   # TLS settings (shared)
│       └── proxy-params.conf # Proxy headers + SSL re-encrypt settings
├── certs/                    # Certs go here — never committed to git
│   └── <hostname>/
│       ├── fullchain.pem
│       └── privkey.pem
└── scripts/
    ├── add-vhost.sh          # Scaffold a new vhost config
    ├── gen-self-signed.sh    # Generate self-signed cert
    ├── gen-letsencrypt.sh    # Obtain Let's Encrypt cert
    └── install-cert.sh       # Copy existing cert into place
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

# Start
docker compose up -d

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

## SSL bridging notes

- nginx terminates the client TLS connection using certs in `certs/<hostname>/`
- Outbound connections to backends use HTTPS
- Backend SSL verification is **disabled by default** (`proxy_ssl_verify off`) because internal backends often use self-signed certs
- To enable verification for a backend, set `proxy_ssl_verify on` and add `proxy_ssl_trusted_certificate /path/to/backend-ca.pem;` in the relevant vhost
