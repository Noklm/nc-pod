#!/bin/bash

NEXTCLOUD_DIR=nextcloud
mkdir -p $NEXTCLOUD_DIR

# Container names
DB_CONTAINER=db
NEXTCLOUD_CONTAINER=app
WEB_SERVER_CONTAINER=web

# Pod name
POD=nextcloud-pod
SITE_PORT=8080
# export SITE_PORT=8080

if podman pod ls | grep -q $POD; then
  	echo "Remove old POD and Containers"
  	podman pod stop $POD
	podman pod rm -f $POD
fi

# Db Env vars
DB_USER=nextcloud
DB_PWD=password
DB_ROOT_PWD=root-pwd
DB_NAME=db
DB_HOST=127.0.0.1

# Nextcloud Env vars
NEXTCLOUD_ADMIN_USER=admin   \
NEXTCLOUD_ADMIN_PASSWORD=admin   \
NEXTCLOUD_TRUSTED_DOMAINS=127.0.0.1 \


# Create the pod
podman pod create \
	--name $POD \
	-p $SITE_PORT:$SITE_PORT

# Starts mariaDB container
podman run -d \
    --name $DB_CONTAINER \
	--pod $POD \
    -e MYSQL_USER=$DB_USER \
    -e MYSQL_PASSWORD=$DB_PWD \
    -e MYSQL_ROOT_PASSWORD=$DB_ROOT_PWD \
    -e MYSQL_DATABASE=$DB_NAME \
    mariadb:10.9 \
	--transaction-isolation=READ-COMMITTED --binlog-format=ROW

# Starts Nextcloud container
podman run -d \
	--name $NEXTCLOUD_CONTAINER \
	--pod $POD \
	-u root \
	--requires $DB_CONTAINER \
	-e MYSQL_USER=$DB_USER \
    -e MYSQL_PASSWORD=$DB_PWD \
	-e MYSQL_ROOT_PASSWORD=$DB_ROOT_PWD \
    -e MYSQL_DATABASE=$DB_NAME \
    -e MYSQL_HOST=$DB_HOST \
    -e NEXTCLOUD_ADMIN_USER=$NEXTCLOUD_ADMIN_USER \
    -e NEXTCLOUD_ADMIN_PASSWORD=$NEXTCLOUD_ADMIN_PASSWORD \
    -e NEXTCLOUD_TRUSTED_DOMAINS=$NEXTCLOUD_TRUSTED_DOMAINS \
	-v "$PWD"/$NEXTCLOUD_DIR:/var/www/html \
	nextcloud:23-fpm-alpine
# -v nextcloud:/var/www/html \
# -v "$PWD"/$NEXTCLOUD_DIR:/var/www/html \
# -v apps:/var/www/html/custom_apps \
# -v config:/var/www/html/config \
# -v data:/var/www/html/data \
# Starts Caddy server container
podman run -d \
	--name $WEB_SERVER_CONTAINER \
	--pod $POD \
	-v "$PWD"/web/dev/Caddyfile:/etc/caddy/Caddyfile \
	-v caddy_data:/data \
	--volumes-from app \
	caddy:2.6-alpine