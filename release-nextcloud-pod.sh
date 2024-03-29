#!/bin/bash
# shellcheck disable=SC1091

source .env

mkdir -p "$MOUNT_POINT"/db "$MOUNT_POINT"/nextcloud "$MOUNT_POINT"/apps "$MOUNT_POINT"/config "$MOUNT_POINT"/data "$MOUNT_POINT"/theme

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
    -e MYSQL_DATABASE="$DB_NAME"\
	-v "$MOUNT_POINT"/db:/var/lib/mysql \
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
	-v "$MOUNT_POINT"/nextcloud:/var/www/html \
	-v "$MOUNT_POINT"/apps:/var/www/html/custom_apps \
	-v "$MOUNT_POINT"/config:/var/www/html/config \
	-v "$MOUNT_POINT"/data:/var/www/html/data \
	-v "$MOUNT_POINT"/theme:/var/www/html/themes/custom_theme \
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
	-e "aliasgroup1=$OFFICE_ALIASGROUP" \
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
	-v "$CADDYFILE_PATH":/etc/caddy/Caddyfile \
	-v caddy_data:/data \
	--volumes-from "$NEXTCLOUD_CONTAINER" \
	-e OVH_ENDPOINT=ovh-eu \
	-e OVH_APPLICATION_KEY="$OVH_APPLICATION_KEY" \
	-e OVH_APPLICATION_SECRET="$OVH_APPLICATION_SECRET" \
	-e OVH_CONSUMER_KEY="$OVH_CONSUMER_KEY" \
	-e DOMAIN="$DOMAIN" \
	-e NC_SUBDOMAIN="$NEXTCLOUD_CONTAINER" \
	-e OFFICE_SUBDOMAIN="$OFFICE_CONTAINER" \
	caddy-ovh:1.0

echo "Nextcloud available at https://$NEXTCLOUD_CONTAINER.$DOMAIN"