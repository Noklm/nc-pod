#!/bin/bash

NEXTCLOUD_DIR=nextcloud
DB_DIR=db
mkdir -p $NEXTCLOUD_DIR
mkdir -p $DB_DIR

# Container names
DB_CONTAINER=db
NEXTCLOUD_CONTAINER=app
WEB_SERVER_CONTAINER=web
REDIS_CONTAINER=redis
CRON_CONTAINER=cron
AUTOSSH_CONTAINER=autossh

# Pod name
POD=nextcloud-pod
POD_PORT=2222

if podman pod ls | grep -q $POD; then
  	echo "Remove old POD and Containers"
  	podman pod stop $POD
	podman pod rm -f $POD
fi

HOST=127.0.0.1

# Db Env vars
DB_USER=nextcloud
DB_PWD=password
DB_ROOT_PWD=root-pwd
DB_NAME=db

# Nextcloud Env vars
NEXTCLOUD_ADMIN_USER=admin   \
NEXTCLOUD_ADMIN_PASSWORD=admin   \
NEXTCLOUD_TRUSTED_DOMAINS=nokrux.fr \

# Autossh Env vars
REMOTE_USER=nextcloud
SERVER_IP=51.77.212.247
SERVER_PORT=$POD_PORT
FORWARD_PORT=443
HOST_PORT=$FORWARD_PORT
SSH_BIND_IP="*"
SSH_KEY_PATH=/home/julien/.ssh/vps_rsa

# Create the pod
podman pod create \
	--name $POD \
	-p $POD_PORT:$POD_PORT

# Starts mariaDB container
podman run -d \
    --name $DB_CONTAINER \
	--pod $POD \
	--restart always \
    -e MYSQL_USER=$DB_USER \
    -e MYSQL_PASSWORD=$DB_PWD \
    -e MYSQL_ROOT_PASSWORD=$DB_ROOT_PWD \
    -e MYSQL_DATABASE=$DB_NAME \
	-v "$PWD"/$DB_DIR:/var/lib/mysql \
    mariadb:10.9 \
	--transaction-isolation=READ-COMMITTED --binlog-format=ROW

# Starts redis container
podman run -d \
    --name $REDIS_CONTAINER \
	--pod $POD \
	--restart always \
    redis:7.0-alpine

# Starts Nextcloud container
podman run -d \
	--name $NEXTCLOUD_CONTAINER \
	--pod $POD \
	--restart always \
	--requires $DB_CONTAINER,$REDIS_CONTAINER \
	-e MYSQL_USER=$DB_USER \
    -e MYSQL_PASSWORD=$DB_PWD \
	-e MYSQL_ROOT_PASSWORD=$DB_ROOT_PWD \
    -e MYSQL_DATABASE=$DB_NAME \
    -e MYSQL_HOST=$HOST \
    -e REDIS_HOST=$HOST \
    -e NEXTCLOUD_ADMIN_USER=$NEXTCLOUD_ADMIN_USER \
    -e NEXTCLOUD_ADMIN_PASSWORD=$NEXTCLOUD_ADMIN_PASSWORD \
    -e NEXTCLOUD_TRUSTED_DOMAINS=$NEXTCLOUD_TRUSTED_DOMAINS \
	-v "$PWD"/$NEXTCLOUD_DIR:/var/www/html \
	nextcloud:23-fpm-alpine

# Starts Nextcloud Cron container
podman run -d \
	--name $CRON_CONTAINER \
	--pod $POD \
	--restart always \
	--requires $DB_CONTAINER,$REDIS_CONTAINER \
	--entrypoint /cron.sh \
	-v "$PWD"/$NEXTCLOUD_DIR:/var/www/html \
	nextcloud:23-fpm-alpine

# Starts Caddy Server container
# podman run -d \
# 	--name $WEB_SERVER_CONTAINER \
# 	--pod $POD \
# 	--restart always \
# 	--requires $NEXTCLOUD_CONTAINER \
# 	-v "$PWD"/web/dev/Caddyfile:/etc/caddy/Caddyfile \
# 	-v caddy_data:/data \
# 	--volumes-from app \
# 	caddy:2.6-alpine

# Starts autoSSH container
podman run -d \
	--name $AUTOSSH_CONTAINER \
	--pod $POD \
	-e SSH_REMOTE_USER=$REMOTE_USER \
	-e SSH_REMOTE_HOST=$SERVER_IP \
	-e SSH_REMOTE_PORT=$SERVER_PORT \
	-e SSH_TUNNEL_PORT=$FORWARD_PORT \
	-e SSH_TARGET_HOST=$HOST \
	-e SSH_TARGET_PORT=$HOST_PORT \
	-e SSH_BIND_IP="$SSH_BIND_IP" \
	-v $SSH_KEY_PATH:/id_rsa \
	jnovack/autossh:2.0.1

# Starts Caddy server container
podman run -d \
	--name $WEB_SERVER_CONTAINER \
	--pod $POD \
	--restart always \
	--requires $NEXTCLOUD_CONTAINER,$AUTOSSH_CONTAINER \
	-v "$PWD"/web/Caddyfile:/etc/caddy/Caddyfile \
	-v caddy_data:/data \
	--volumes-from $NEXTCLOUD_CONTAINER \
	caddy-ovh:1.0
echo "Nextcloud available at https://nokrux.fr"