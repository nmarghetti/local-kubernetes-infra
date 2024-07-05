#! /bin/bash

cd "$(dirname "$(readlink -f "$0")")" || {
  echo "Unable to go to parent folder of $0" >&2
  exit 1
}

# Wait for all flux kustomization to reconcile
while read -r line; do
  # shellcheck disable=SC2086
  set $line
  echo "Waiting for $1/$2 to reconcile..."
  flux reconcile kustomization -n "$1" "$2" --timeout 15m
  echo
done < <(kubectl get -A kustomizations.kustomize.toolkit.fluxcd.io --no-headers -o custom-columns=NAME:.metadata.namespace,RSRC:.metadata.name)
