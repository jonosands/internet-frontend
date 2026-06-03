# syntax=docker/dockerfile:1
#
# internet-frontend nginx image with the MaxMind GeoIP2 module compiled in.
#
# The stock nginx:stable-alpine image does NOT ship ngx_http_geoip2_module, so
# we build it as a loadable dynamic module. The base image is built
# `--with-compat`, which freezes the module ABI — meaning a minimally-configured
# module (just `--with-compat`) loads into the prebuilt nginx without having to
# replicate its full original ./configure args.
#
# The module source version MUST match the running nginx version, so we derive
# it from `nginx -V` inside the base image rather than hard-coding it. A base
# image bump (e.g. 1.30.1 -> 1.32.x via `docker compose build --pull`) therefore
# rebuilds a matching module automatically instead of producing a
# "module is not binary compatible" load failure.
#
# Module: https://github.com/leev/ngx_http_geoip2_module  (tag 3.4, current)

ARG GEOIP2_TAG=3.4

# ---- builder stage --------------------------------------------------------
FROM nginx:stable-alpine AS builder
ARG GEOIP2_TAG

# Build toolchain + libmaxminddb headers. pcre2/zlib/openssl -dev are required
# for ./configure to complete even though we only run `make modules`.
RUN apk add --no-cache \
        gcc \
        make \
        libc-dev \
        linux-headers \
        pcre2-dev \
        zlib-dev \
        openssl-dev \
        libmaxminddb-dev \
        git \
        curl

WORKDIR /usr/src

# Build both the HTTP and STREAM geoip2 modules against the exact nginx source
# version baked into this base image. `--with-stream=dynamic` is what makes the
# module's config emit ngx_stream_geoip2_module.so in addition to the http one.
RUN set -eux; \
    NGINX_VERSION="$(nginx -V 2>&1 | sed -n 's|.*nginx/\([0-9.]*\).*|\1|p')"; \
    echo "Building geoip2 ${GEOIP2_TAG} against nginx ${NGINX_VERSION}"; \
    curl -fSL "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" -o nginx.tar.gz; \
    tar -xzf nginx.tar.gz; \
    git clone --depth 1 --branch "${GEOIP2_TAG}" \
        https://github.com/leev/ngx_http_geoip2_module.git; \
    cd "nginx-${NGINX_VERSION}"; \
    ./configure \
        --with-compat \
        --with-stream=dynamic \
        --add-dynamic-module=../ngx_http_geoip2_module; \
    make modules; \
    mkdir -p /build-modules; \
    cp objs/ngx_http_geoip2_module.so objs/ngx_stream_geoip2_module.so /build-modules/; \
    ls -l /build-modules

# ---- final stage ----------------------------------------------------------
FROM nginx:stable-alpine

# Runtime shared library so nginx can dlopen the modules.
RUN apk add --no-cache libmaxminddb

COPY --from=builder /build-modules/ngx_http_geoip2_module.so   /usr/lib/nginx/modules/
COPY --from=builder /build-modules/ngx_stream_geoip2_module.so /usr/lib/nginx/modules/

# nginx.conf (mounted at runtime) must `load_module` these in the main context.
# GeoLite2 .mmdb files are supplied at runtime via the ./geoip volume mount;
# see scripts/update-geoip.sh.
