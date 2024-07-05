#! /bin/bash

install_podinfo_with_kubectl() {
  if ! kubectl get namespaces info >/dev/null 2>&1; then
    # kubectl delete namespace info
    kubectl create namespace info
    kubectl annotate namespace info local/hostname="$(hostname)"
    kubectl label namespace info local/user="$USER"
    if [ -z "$PODINFO_UI_MESSAGE" ]; then
      kubectl --namespace info create deployment --replicas 1 --port 9898 --image stefanprodan/podinfo podinfo
    else
      kubectl --namespace info create deployment --replicas 1 --port 9898 --image stefanprodan/podinfo podinfo --dry-run=client -o yaml | kubectl set env --local -f - PODINFO_UI_MESSAGE="$PODINFO_UI_MESSAGE" -o yaml | kubectl apply -f -
    fi
    kubectl --namespace info expose deployment podinfo --type ClusterIP --port 9898
    kubectl --namespace info create ingress --class nginx --rule 'podinfo.minikube/*=podinfo:9898' minikube-podinfo
  # kubectl --namespace info create ingress --class nginx --rule 'podinfo.localhost/*=podinfo:9898' kind-podinfo
  fi
}

# Allow to add annotations and labels
metada=$(
  cat <<EOM | yq -o json | jq -r tostring
metadata:
  annotations:
    local/hostname: $(hostname)
    local/generation-tool: kubectl
  labels:
    local/user: $USER
EOM
)
add_medata() {
  yq -o json | jq '. * '"$metada"'' | yq -P
}

create_podinfo_manifest() {
  local dir="${1:-manifests}"
  mkdir -p "${dir}"
  kubectl create --dry-run=client -o yaml namespace info >"${dir}"/namespace.yaml
  kubectl create --dry-run=client -o yaml deployment --replicas 1 --port 9898 --image stefanprodan/podinfo podinfo >"${dir}"/deployment.yaml
  kubectl create --dry-run=client -o yaml service clusterip --tcp 9898:9898 podinfo >"${dir}"/service.yaml
  kubectl create --dry-run=client -o yaml ingress --class nginx --rule 'podinfo.minikube/*=podinfo:9898' minikube-podinfo >"${dir}"/ingress.yaml
  printf -- "---\n" >>"${dir}"/ingress.yaml
  kubectl create --dry-run=client -o yaml ingress --class nginx --rule 'podinfo.localhost/*=podinfo:9898' kind-podinfo >>"${dir}"/ingress.yaml
}

create_podinfo_manifest_with_metada() {
  local dir="${1:-manifests}"
  mkdir -p "${dir}"
  kubectl create --dry-run=client -o yaml namespace info | add_medata >"${dir}"/namespace.yaml
  kubectl create --dry-run=client -o yaml deployment --replicas 1 --port 9898 --image stefanprodan/podinfo podinfo | add_medata >"${dir}"/deployment.yaml
  kubectl create --dry-run=client -o yaml service clusterip --tcp 9898:9898 podinfo | add_medata >"${dir}"/service.yaml
  kubectl create --dry-run=client -o yaml ingress --class nginx --rule 'podinfo.minikube/*=podinfo:9898' minikube-podinfo | add_medata >"${dir}"/ingress.yaml
  printf -- "---\n" >>"${dir}"/ingress.yaml
  kubectl create --dry-run=client -o yaml ingress --class nginx --rule 'podinfo.localhost/*=podinfo:9898' kind-podinfo | add_medata >>"${dir}"/ingress.yaml
}

apply_manifests() {
  local dir="${1:-manifests}"
  kubectl apply -f "${dir}"/namespace.yaml
  for manifest in deployment service ingress; do
    kubectl apply --namespace info -f "${dir}/${manifest}.yaml"
  done
}

create_kustomization() {
  local dir="${1:-kustomization}"
  local base_dir="${dir}/base"
  local kustom_dir="${dir}/kustom"
  mkdir -p "${base_dir}" "${kustom_dir}"
  cat <<EOM >"${base_dir}"/kustomization.yaml
resources:
  - deployment.yaml
  - service.yaml
  - ingress.yaml
commonAnnotations:
  local/hostname: $(hostname)
  local/generation-tool: kustomize
commonLabels:
  local/user: $USER
EOM
  create_podinfo_manifest "$base_dir"
  rm -f "${base_dir}"/namespace.yaml

  # https://kubectl.docs.kubernetes.io/references/kustomize/kustomization/patches/
  cat <<EOM >"${kustom_dir}"/kustomization.yaml
resources:
  - namespace.yaml
  - ../base
namespace: kustom-info
patches:
  - target:
      group: networking.k8s.io
      version: v1
      kind: Ingress
      name: minikube-podinfo
    patch: |-
      - op: replace
        path: /spec/rules/0/host
        value: kustom-podinfo.minikube
      - op: replace
        path: /metadata/name
        value: kustom-minikube-podinfo
  - target:
      group: networking.k8s.io
      version: v1
      kind: Ingress
      name: kind-podinfo
    path: ingress_patch.json
  - path: service_patch.yaml
EOM
  cat <<EOM | yq -o json | jq -r . >"${kustom_dir}"/ingress_patch.json
- op: replace
  path: /spec/rules/0/host
  value: kustom-podinfo.localhost
- op: replace
  path: /metadata/name
  value: kustom-kind-podinfo
EOM
  cat <<EOM >"${kustom_dir}"/service_patch.yaml
apiVersion: v1
kind: Service
metadata:
  name: podinfo
  labels:
    extra-label: some-label
EOM
  kubectl create --dry-run=client -o yaml namespace name-overriden-by-kustomize >"${kustom_dir}"/namespace.yaml
}

apply_kustomization() {
  local dir="${1:-kustomization}"
  kubectl kustomize "${dir}/kustom" | kubectl apply -f -
  # kubectl apply -k "${dir}/kustom"
}

# If the script is not being sourced, run the setup
(return 0 2>/dev/null) || {
  # set -eoxu pipefail

  cd "$(dirname "$(readlink -f "$0")")" || {
    echo "Unable to go to parent folder of $0" >&2
    exit 1
  }

  for namespace in $(kubectl get namespaces -o json | jq '.items[] | select(.metadata.name == "info" or .metadata.name == "kustom-info") | .metadata.name' -r); do
    kubectl delete namespace --wait=true "$namespace"
  done

  # create_podinfo_manifest "manifests"
  # apply_manifests "manifests"
  create_podinfo_manifest_with_metada "manifests"
  apply_manifests "manifests"

  create_kustomization "kustomization"
  apply_kustomization "kustomization"

  exit 0
}
