#! /bin/bash

cd "$(dirname "$(readlink -f "$0")")/.." || {
  echo "Unable to go to parent parent folder of $0" >&2
  exit 1
}

# shellcheck source=./common.sh
. ./scripts/common.sh

type flux >/dev/null 2>&1 || exit_error "Please install flux first"

flux_version=$(flux version --client -o json | jq '.flux' | xargs printf "%s" | sed -re 's/^v(.*)$/\1/')
flux_path="./k8s/flux/base/flux-system/$flux_version"
[ -f "$flux_path"/gotk-components.yaml ] && exit 0

mkdir -p "$flux_path"
flux install --export >"$flux_path"/gotk-components.yaml
cat <<-EOM >"$flux_path"/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - gotk-components.yaml
EOM
git add "$flux_path"
git commit -m "Add flux components $flux_path"

exit 0
