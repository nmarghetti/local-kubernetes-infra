#! /bin/bash

cd "$(dirname "$(readlink -f "$0")")" || {
  echo "Unable to go to parent folder of $0" >&2
  exit 1
}

set -eoxu pipefail

INGRESS_NGINX_VERSION=v1.10.1
# https://github.com/kubernetes/ingress-nginx/tree/main/deploy/static/provider/kind
curl -sSL "https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-${INGRESS_NGINX_VERSION}/deploy/static/provider/kind/deploy.yaml" -o nginx.yaml
