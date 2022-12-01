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

# Pod name
POD=nextcloud-pod
SITE_PORT=8080
# export SITE_PORT=8080

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
NEXTCLOUD_TRUSTED_DOMAINS=127.0.0.1 \


# Create the pod
podman pod create \
	--name $POD \
	-p $SITE_PORT:$SITE_PORT

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

# -v nextcloud:/var/www/html \
# -v "$PWD"/$NEXTCLOUD_DIR:/var/www/html \
# -v apps:/var/www/html/custom_apps \
# -v config:/var/www/html/config \
# -v data:/var/www/html/data \
# Starts Caddy server container

podman run -d \
	--name $WEB_SERVER_CONTAINER \
	--pod $POD \
	--restart always \
	--requires $NEXTCLOUD_CONTAINER \
	-v "$PWD"/web/dev/Caddyfile:/etc/caddy/Caddyfile \
	-v caddy_data:/data \
	--volumes-from app \
	caddy:2.6-alpine

# 	-v "$PWD"/$NEXTCLOUD_DIR:/var/www/html:z,ro \
echo "Nextcloud now running at http://127.0.0.1:8080"