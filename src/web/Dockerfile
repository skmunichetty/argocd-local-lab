# --- Stage 1: build the static React files ---
FROM node:24-alpine AS build
WORKDIR /src
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
ARG APP_VERSION=dev
ENV VITE_APP_VERSION=$APP_VERSION
RUN npm run build

# --- Stage 2: serve them with nginx (non-root variant, listens on 8080) ---
FROM nginxinc/nginx-unprivileged:1.29-alpine
# Files in /etc/nginx/templates are processed with envsubst at startup.
COPY nginx/default.conf.template /etc/nginx/templates/default.conf.template
COPY --from=build /src/dist /usr/share/nginx/html
EXPOSE 8080
