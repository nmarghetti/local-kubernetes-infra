#! /bin/sh

cd "$(dirname "$(readlink -f "$0")")" || {
  echo "Unable to go to parent folder of $0" >&2
  exit 1
}

# DOCKER_GID=$(stat -c '%g' /var/run/docker.sock)
DOCKER_GID=$(getent group docker | cut -d':' -f3)
export DOCKER_GID
# shellcheck disable=SC2016
envsubst '${DOCKER_GID}' <./devcontainer.template.json >./devcontainer.json
