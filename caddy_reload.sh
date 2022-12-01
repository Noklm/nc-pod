#!/bin/bash

caddy_container_id=$(podman ps | grep caddy | awk '{print $1;}')
echo "Caddy container id: $caddy_container_id"
podman exec -w /etc/caddy "$caddy_container_id" caddy reload
echo "Caddy reloaded"