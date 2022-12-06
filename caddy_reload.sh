#!/bin/bash

podman exec -w /etc/caddy web caddy reload
echo "Caddy reloaded"