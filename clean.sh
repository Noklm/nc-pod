#!/bin/bash

NEXTCLOUD_DIR=nextcloud
DB_DIR=db

# Pod name
POD=nextcloud-pod
# export SITE_PORT=8080

if podman pod ls | grep -q $POD; then
  	podman pod stop $POD
	podman pod rm -f $POD
	podman volume rm -a
fi

[ -d "$NEXTCLOUD_DIR" ] && sudo rm -r $NEXTCLOUD_DIR
[ -d "$DB_DIR" ] && sudo rm -r $DB_DIR
