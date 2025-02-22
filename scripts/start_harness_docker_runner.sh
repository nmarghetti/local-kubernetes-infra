#! /bin/bash

cd "$(dirname "$(readlink -f "$0")")/.." || {
  echo "Unable to go to parent parent folder of $0" >&2
  exit 1
}

HTTPS_BIND=${1:-3250}

[ -f ./tmp/harness-docker-runner ] || curl -Lo ./tmp/harness-docker-runner https://github.com/harness/harness-docker-runner/releases/latest/download/harness-docker-runner-linux-amd64
sudo HTTPS_BIND=":$HTTPS_BIND" DRONE_DEBUG=true ./tmp/harness-docker-runner server | grcat ./scripts/grc.logrus.conf
