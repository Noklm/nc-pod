#!/bin/bash
# shellcheck disable=SC1091

# Pod name
source .env

if podman pod ls | grep -q "$POD"; then
  	podman pod stop "$POD"
	podman pod rm -f "$POD"
fi

[ -d "$MOUNT_POINT" ] && sudo rm -r "$MOUNT_POINT"
