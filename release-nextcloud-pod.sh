#!/bin/bash
podman pod stop nextcloud-pod
podman rm db app web 

DIR=nextcloud
if [ -d "$DIR" ];
then
    echo "$DIR directory exists"
else
	echo "Creating $DIR directory"
    mkdir nextcloud
fi

# Create the pod
podman pod create \
	--name nextcloud-pod \
	-p 2222:2222

# Starts mariaDB container
podman run -d \
    --name db \
	--pod nextcloud-pod \
    -e MYSQL_USER=nextcloud \
    -e MYSQL_PASSWORD=pwd \
    -e MYSQL_ROOT_PASSWORD=root-pwd \
    -e MYSQL_DATABASE=db \
    mariadb:10.9 \
	--transaction-isolation=READ-COMMITTED --binlog-format=ROW

# Starts Nextcloud container
podman run -d \
	--pod nextcloud-pod \
	--name app \
	-e MYSQL_ROOT_PASSWORD=root-pwd \
    -e MYSQL_PASSWORD=pwd   \
    -e MYSQL_HOST=127.0.0.1 \
    -e MYSQL_DATABASE=db    \
    -e MYSQL_USER=nextcloud \
    -e NEXTCLOUD_ADMIN_USER=admin   \
    -e NEXTCLOUD_ADMIN_PASSWORD=admin   \
    -e NEXTCLOUD_TRUSTED_DOMAINS=https://nokrux.fr  \
	-v /home/julien/Documents/services/nextcloud:/var/www/html \
	-v apps:/var/www/html/custom_apps \
	-v config:/var/www/html/config \
	-v data:/var/www/html/data \
	nextcloud:23-fpm-alpine

# Starts Caddy server container
podman run -d \
	--pod nextcloud-pod \
	--name web \
	-v "$PWD"/web/Caddyfile:/etc/caddy/Caddyfile \
	-v caddy_data:/data \
	--volumes-from app \
	caddy-ovh:1.0

# Starts autoSSH container
podman run -d \
	--name autossh \
	--pod nextcloud-pod \
	-e SSH_REMOTE_USER=nextcloud \
	-e SSH_REMOTE_HOST=51.77.212.247 \
	-e SSH_REMOTE_PORT=2222 \
	-e SSH_TUNNEL_PORT=443 \
	-e SSH_TARGET_HOST=127.0.0.1 \
	-e SSH_TARGET_PORT=443 \
	-e SSH_BIND_IP=* \
	-v /home/julien/.ssh/vps_rsa:/id_rsa \
	jnovack/autossh:2.0.1