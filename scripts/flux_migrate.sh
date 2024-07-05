#! /bin/bash

cd "$(dirname "$(readlink -f "$0")")/.." || {
  echo "Unable to go to parent parent folder of $0" >&2
  exit 1
}

# shellcheck source=./common.sh
. ./scripts/common.sh

usage() {
  cat <<EOM
Usage: $0 [options]

Options:
  -p, --flux-path <path> : path to flux components to upgrade, if not specified it will take it from the cluster
  -f, --force            : it will remove existing flux installation
  -h                     : display this help
EOM
}

parse_args() {
  flux_path=
  force=0
  # reset getopts - check https://man.cx/getopts(1)
  OPTIND=1
  while getopts "hfp:-:" opt; do
    case "$opt" in
      p) flux_path="$OPTARG" ;;
      f) force=1 ;;
      -)
        case "$OPTARG" in
          flux-path)
            flux_path="${!OPTIND}"
            OPTIND=$((OPTIND + 1))
            ;;
          force) force=1 ;;
          *)
            echo "Unknow option $OPTARG"
            usage
            exit 1
            ;;
        esac
        ;;
      \? | *)
        usage
        exit 1
        ;;
    esac
  done
  shift $((OPTIND - 1))
  [ $# -ne 0 ] && {
    echo "Error: No argument accepted." >&2
    usage
    exit 1
  }
  [ -z "$flux_path" ] && flux_path=$(kubectl get -n flux-system kustomizations.kustomize.toolkit.fluxcd.io flux-system -o json | jq -r '.spec.path')
  [ -z "$flux_path" ] && exit_error "You must provide a flux system path"
  [ ! -d "$flux_path" ] && exit_error "You must provide an existing flux system path"
  return 0
}

parse_args "$@"

[ "$FULL_DEBUG" = '1' ] && set -eoxu pipefail

if [ -d "$flux_path/flux-system/flux-system" ]; then
  flux_path="$flux_path/flux-system"
  log_info "Changing flux path to $flux_path"
fi

if [ "$force" -eq 1 ]; then
  run_command kubectl get secrets -n flux-system flux-system -o yaml | grep -v -e 'creationTimestamp:' -e 'resourceVersion:' -e 'uid:' >tmp/flux-system-secret.yaml
  run_command flux uninstall --silent
fi

# Ensure to have flux components for the current version
"$GIT_ROOT"/scripts/flux_create_components.sh || exit_error "Unable to create flux components"

# Ensure to have the right flux version
flux_version=$(flux version --client -o json | jq '.flux' | xargs printf "%s" | sed -re 's/^v(.*)$/\1/')
grep -q "flux/base/flux-system/$flux_version" ./k8s/flux/base/flux-system/customized/kustomization.yaml || run_command sed -i -re 's#- .*flux/base/flux-system.*#- ../../../../flux/base/flux-system/'"$flux_version"'#' ./k8s/flux/base/flux-system/customized/kustomization.yaml

# Update the path to the flux components
relative_path=$(for _ in $(seq 1 "$(echo "$flux_path"/flux-system | sed -re 's#.*k8s/(.*)$#\1#' | tr '/' '\n' | wc -l)"); do printf '../'; done)
# grep -q 'gotk-components.yaml' "$flux_path"/flux-system/kustomization.yaml && run_command sed -i -re 's#- gotk-components.yaml#- '"$relative_path"'flux/base/flux-system/'"$flux_version"'#' "$flux_path"/flux-system/kustomization.yaml
# grep -q "flux/base/flux-system/$flux_version" "$flux_path"/flux-system/kustomization.yaml || run_command sed -i -re 's#- .*flux/base/flux-system.*#- '"$relative_path"'flux/base/flux-system/'"$flux_version"'#' "$flux_path"/flux-system/kustomization.yaml
grep -q 'gotk-components.yaml' "$flux_path"/flux-system/kustomization.yaml && run_command sed -i -re 's#- gotk-components.yaml#- '"$relative_path"'flux/base/flux-system/customized#' "$flux_path"/flux-system/kustomization.yaml
[ -f "$flux_path"/flux-system/gotk-components.yaml ] && rm -f "$flux_path"/flux-system/gotk-components.yaml

if [ "$(git diff --stat "$flux_path/flux-system" ./k8s/flux/base/flux-system/customized/kustomization.yaml | wc -l)" -ne 0 ]; then
  run_command git add "$flux_path"/flux-system ./k8s/flux/base/flux-system/customized/kustomization.yaml
  run_command git commit -m "Use flux manifest from k8s/flux/base/flux-system/$flux_version"
  run_command git push gitea main
fi

if [ "$force" -eq 1 ]; then
  # Wait for flux to be uninstalled
  printf 'Waiting for flux to be uninstalled'
  for count in seq 1 30; do
    kubectl get namespace flux-system >/dev/null 2>&1 || break
    printf '.'
    sleep 1
  done
  for count in seq 1 5; do
    printf '.'
    sleep 1
  done
  printf '\n'
  run_command kubectl apply -k "$flux_path"/flux-system
  run_command kubectl apply -f tmp/flux-system-secret.yaml
fi

# Ensure to apply certificates to flux
"$GIT_ROOT"/scripts/flux_apply_certificates.sh

exit 0
