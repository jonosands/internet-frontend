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

# Test config before reloading
docker compose exec nginx nginx -t

# Reload after changes
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

## SSL bridging notes

- nginx terminates the client TLS connection using certs in `certs/<hostname>/`
- Outbound connections to backends use HTTPS
- Backend SSL verification is **disabled by default** (`proxy_ssl_verify off`) because internal backends often use self-signed certs
- To enable verification for a backend, set `proxy_ssl_verify on` and add `proxy_ssl_trusted_certificate /path/to/backend-ca.pem;` in the relevant vhost
