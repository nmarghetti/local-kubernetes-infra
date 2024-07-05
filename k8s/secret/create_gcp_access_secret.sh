#! /bin/sh

cd "$(dirname "$(readlink -f "$0")")" || {
  echo "Unable to go to parent folder of $0" >&2
  exit 1
}

SCRIPTS=$(git rev-parse --show-toplevel)/scripts
# shellcheck source=../../scripts/common.sh
. "$SCRIPTS"/common.sh

secret_file="$PWD/secret-access-credentials.json"

if [ ! -f "$secret_file" ]; then
  exit_error "You need to create $secret_file file that contains you GCP service account credentials"
fi

[ -n "$flux_path" ] || exit_error "flux_path is not set"
[ -d "$GIT_ROOT/$flux_path" ] || exit_error "Flux path '$GIT_ROOT/$flux_path' does not exist"

get_flux_root() {
  {
    cd "$GIT_ROOT/$flux_path"
    [ "$(basename "$PWD")" = 'flux-system' ] && cd ..
    pwd
  }
}
flux_root=$(get_flux_root)
[ -e "$flux_root" ] || exit_error "Flux path '$flux_root' does not exist"

find "$flux_root" -name kustomization.yaml -exec grep -q secret-store.yaml {} \; -print | while IFS= read -r kustomization; do
  namespace=$(yq .namespace <"$kustomization")
  log_info "$(printf "Generating secret for %s\n" "$kustomization in namespace $namespace")"
  kubectl get namespace "$namespace" >/dev/null 2>&1 || kubectl create namespace "$namespace"
  kubectl delete secret gcpsm-secret -n "$namespace" >/dev/null 2>&1
  kubectl create secret generic gcpsm-secret --from-file="$secret_file" -n "$namespace"
done
