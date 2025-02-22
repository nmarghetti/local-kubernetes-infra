#! /bin/bash

cd "$(dirname "$(readlink -f "$0")")" || {
  echo "Unable to go to parent folder of $0" >&2
  exit 1
}

exit_error() {
  echo "$@" >&2
  exit 1
}

GIT_ROOT="$(git rev-parse --show-toplevel)"

# Ensure to have local docker image built
"$GIT_ROOT"/docker/docker-build.sh flux-automated 2024-12-25-08-00.0 || exit_error "Unable to build flux-automated image"
"$GIT_ROOT"/docker/docker-build.sh myproject-automated 1.0.0 || exit_error "Unable to build myproject-automated image"

# Wait for all flux kustomization to reconcile
while read -r line; do
  # shellcheck disable=SC2086
  set $line
  echo "Waiting for $1/$2 to reconcile..."
  flux reconcile kustomization -n "$1" "$2" --timeout 15m
  echo
done < <(kubectl get -A kustomizations.kustomize.toolkit.fluxcd.io --no-headers -o custom-columns=NAME:.metadata.namespace,RSRC:.metadata.name)
