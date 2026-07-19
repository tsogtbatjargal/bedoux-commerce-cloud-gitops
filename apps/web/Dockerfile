# syntax=docker/dockerfile:1
FROM docker.io/library/node:24-alpine AS builder

WORKDIR /build
COPY package.json package-lock.json ./
# `npm ci` refuses on ANY lockfile drift, including optional-only native
# binary entries (e.g. lightningcss/esbuild platform packages) that
# legitimately differ between the host's glibc and this image's musl libc.
# `npm install` resolves those correctly instead of hard-failing the build.
RUN npm install
COPY . .
RUN npm run build

FROM docker.io/nginxinc/nginx-unprivileged:1.27-alpine AS runtime

# The pinned base image tag lags current Alpine security patches (trivy found
# 35 HIGH/CRITICAL CVEs, all with fixes available). Upgrade in place rather
# than floating the tag, so the build stays reproducible; needs root
# temporarily, then drops back to the image's non-root nginx user.
USER root
RUN apk update && apk upgrade --no-cache && rm -rf /var/cache/apk/*
USER nginx

COPY --from=builder /build/dist /usr/share/nginx/html
# Deliberately NOT under /etc/nginx/templates/ — the base image's own
# docker-entrypoint.d script auto-renders *.template files there with an
# unscoped envsubst, which would mangle nginx's own $host/$uri variables
# (they share ${VAR} syntax with real env vars). We render it ourselves
# below with an explicit variable whitelist instead.
COPY nginx.conf.template /etc/nginx/template.src/default.conf.template

# nginx-unprivileged already runs as uid 101 (non-root) and listens on a
# high port by default; our template pins it to 8080 explicitly.
ENV API_UPSTREAM=api:8000

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s \
  CMD wget -q -O /dev/null http://127.0.0.1:8080/ || exit 1

# Explicit variable list — do NOT let envsubst touch nginx's own $host /
# $uri / $proxy_add_x_forwarded_for, which share the same ${VAR} syntax.
CMD ["sh", "-c", "envsubst '${API_UPSTREAM}' < /etc/nginx/template.src/default.conf.template > /etc/nginx/conf.d/default.conf && exec nginx -g 'daemon off;'"]
