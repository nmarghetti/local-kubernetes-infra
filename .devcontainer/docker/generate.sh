#! /bin/sh

cd "$(dirname "$(readlink -f "$0")")" || {
  echo "Unable to go to parent folder of $0" >&2
  exit 1
}

DOCKER_GID=$(getent group docker | cut -d':' -f3)
export DOCKER_GID
envsubst '${DOCKER_GID}' <./devcontainer.template.json >./devcontainer.json
