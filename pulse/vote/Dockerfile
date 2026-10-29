# Image finale toujours linux/amd64 (nodes K8s).
# Le stage build tourne sur l’arch hôte ($BUILDPLATFORM) pour éviter
# le crash esbuild sous QEMU quand on build depuis un Mac arm64.

# --- build (natif Mac / Linux) ---
FROM --platform=linux/amd64 node:20-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
ARG VITE_API_URL=/api
ENV VITE_API_URL=$VITE_API_URL
RUN npm run build

# --- runtime (amd64) ---
FROM --platform=linux/amd64 nginx:1.27-alpine
COPY nginx.conf /etc/nginx/templates/default.conf.template
COPY 05-dns-resolver.envsh /docker-entrypoint.d/05-dns-resolver.envsh
RUN chmod +x /docker-entrypoint.d/05-dns-resolver.envsh
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://127.0.0.1/healthz || exit 1
CMD ["nginx", "-g", "daemon off;"]
