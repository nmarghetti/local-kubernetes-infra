#! /bin/bash

cd "$(dirname "$(readlink -f "$0")")" || {
  echo "Unable to go to parent folder of $0" >&2
  exit 1
}

set -eoxu pipefail

declare -A CRD_VERSION=(
  ["cert-manager"]="v1.14.5"
  ["redis-operator"]="v1.3.0-rc1"
  ["external-secrets"]="v0.9.13"
  ["traefik"]="v31.1.1"
)

declare -A CRD_DOWNLOAD=(
  ["cert-manager"]="get"
  ["redis-operator"]="get"
  ["external-secrets"]="get"
  ["traefik"]="list"
)

declare -A CRD_URL=(
  ["cert-manager"]="https://github.com/cert-manager/cert-manager/releases/download/${CRD_VERSION["cert-manager"]}/cert-manager.yaml"
  ["redis-operator"]="https://raw.githubusercontent.com/spotahome/redis-operator/${CRD_VERSION["redis-operator"]}/manifests/databases.spotahome.com_redisfailovers.yaml"
  ["external-secrets"]="https://raw.githubusercontent.com/external-secrets/external-secrets/${CRD_VERSION["external-secrets"]}/deploy/crds/bundle.yaml"
  ["traefik"]="https://api.github.com/repos/traefik/traefik-helm-chart/contents/traefik/crds?ref=${CRD_VERSION["traefik"]}"
)

for crd in "${!CRD_URL[@]}"; do
  rm -rf "$crd"
  mkdir -p "$crd"
  if [ "${CRD_DOWNLOAD[$crd]}" = "get" ]; then
    curl -sSL "${CRD_URL[$crd]}" -o "${crd}/crd.yaml"
  elif [ "${CRD_DOWNLOAD[$crd]}" = "list" ]; then
    for url in $(curl -sSL "${CRD_URL[$crd]}" | jq -r '.[] | .download_url'); do
      curl -sSL "$url" -o "${crd}/$(basename "$url")"
    done
  fi
  cat <<EOF >"${crd}/kustomization.yaml"
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
$(command ls -1 "$crd" | grep -vFx 'kustomization.yaml' | sed -re 's/^(.*)$/  - \1/')
EOF
done
