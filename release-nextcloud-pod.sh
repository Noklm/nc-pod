#!/bin/bash
# shellcheck disable=SC1091

source .env

mkdir -p "$NEXTCLOUD_DIR"
mkdir -p "$DB_DIR"

if podman pod ls | grep -q "$POD"; then
  	echo "Remove old POD and Containers"
  	podman pod stop "$POD"
	podman pod rm -f "$POD"
fi

# Create the pod
podman pod create \
	--name "$POD" \
	-p "$POD_PORT":"$POD_PORT"

# Starts mariaDB container
podman run -d \
    --name "$DB_CONTAINER" \
	--pod "$POD" \
	--restart always \
    -e MYSQL_USER="$DB_USER" \
    -e MYSQL_PASSWORD="$DB_PWD" \
    -e MYSQL_ROOT_PASSWORD="$DB_ROOT_PWD" \
    -e MYSQL_DATABASE="$DB_NAME "\
	-v "$PWD"/"$DB_DIR":/var/lib/mysql \
    mariadb:10.9 \
	--transaction-isolation=READ-COMMITTED --binlog-format=ROW

# Starts redis container
podman run -d \
    --name "$REDIS_CONTAINER" \
	--pod "$POD" \
	--restart always \
    redis:7.0-alpine

# Starts Nextcloud container
# Nextcloud docker instructions: https://github.com/nextcloud/docker
podman run -d \
	--name "$NEXTCLOUD_CONTAINER" \
	--pod "$POD" \
	--restart always \
	--requires "$DB_CONTAINER","$REDIS_CONTAINER" \
	-e MYSQL_USER="$DB_USER" \
    -e MYSQL_PASSWORD="$DB_PWD" \
	-e MYSQL_ROOT_PASSWORD="$DB_ROOT_PWD" \
    -e MYSQL_DATABASE="$DB_NAME" \
    -e MYSQL_HOST="$HOST" \
    -e REDIS_HOST="$HOST" \
    -e NEXTCLOUD_ADMIN_USER="$NEXTCLOUD_ADMIN_USER" \
    -e NEXTCLOUD_ADMIN_PASSWORD="$NEXTCLOUD_ADMIN_PASSWORD" \
    -e NEXTCLOUD_TRUSTED_DOMAINS="$NEXTCLOUD_CONTAINER"."$DOMAIN" \
	-v "$PWD"/"$NEXTCLOUD_DIR":/var/www/html \
	nextcloud:23-fpm-alpine

# Starts Nextcloud Cron container
podman run -d \
	--name "$CRON_CONTAINER" \
	--pod "$POD" \
	--restart always \
	--requires "$DB_CONTAINER","$REDIS_CONTAINER" \
	--entrypoint /cron.sh \
	-v "$PWD"/"$NEXTCLOUD_DIR":/var/www/html \
	nextcloud:23-fpm-alpine

# Starts AutoSSH container
# Instructions: https://github.com/jnovack/autossh
podman run -d \
	--name "$AUTOSSH_CONTAINER" \
	--pod "$POD" \
	--restart always \
	-e SSH_REMOTE_USER="$REMOTE_USER" \
	-e SSH_REMOTE_HOST="$SERVER_IP" \
	-e SSH_REMOTE_PORT="$POD_PORT" \
	-e SSH_TUNNEL_PORT="$FORWARD_PORT" \
	-e SSH_TARGET_HOST="$HOST" \
	-e SSH_TARGET_PORT="$FORWARD_PORT" \
	-e SSH_BIND_IP="$SSH_BIND_IP" \
	-v "$SSH_KEY_PATH":/id_rsa \
	jnovack/autossh:2.0.1

# Collabora on docker instructions: https://sdk.collaboraonline.com/docs/installation/CODE_Docker_image.html
podman run -d \
	--name "$OFFICE_CONTAINER" \
	--pod "$POD" \
	--restart always \
	--cap-add MKNOD \
	-e "aliasgroup1=$OFFICE_DOMAIN" \
	-e "username=$OFFICE_USERNAME" \
	-e "password=$OFFICE_PWD" \
	-e "dictionaries=fr_FR,en_US" \
    -e "extra_params=--o:ssl.enable=true --o:ssl.termination=true"  \
	collabora/code:22.05.8.4.1


podman run -d \
	--name "$WEB_SERVER_CONTAINER" \
	--pod "$POD" \
	--restart always \
	--requires "$NEXTCLOUD_CONTAINER","$AUTOSSH_CONTAINER" \
	-v "$PWD"/web/Caddyfile:/etc/caddy/Caddyfile \
	-v caddy_data:/data \
	--volumes-from "$NEXTCLOUD_CONTAINER" \
	-e APP_KEY="$APP_KEY" \
	-e APP_SECRET="$APP_SECRET" \
	-e CONSUMER_KEY="$CONSUMER_KEY" \
	-e DOMAIN="$DOMAIN" \
	caddy-ovh:1.0

echo "Nextcloud available at https://$NEXTCLOUD_TRUSTED_DOMAINS"