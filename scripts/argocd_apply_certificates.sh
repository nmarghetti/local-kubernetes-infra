#! /bin/bash

cd "$(dirname "$(readlink -f "$0")")" || {
  echo "Unable to go to parent folder of $0" >&2
  exit 1
}

. ./common.sh

refresh=0
pod=

[ "$FULL_DEBUG" = '1' ] && set -eoxu pipefail

if ! kubectl get namespaces argocd &>/dev/null; then
  run_command kubectl create namespace argocd || exit_error "Unable to create namespace argocd"
fi

# Refresh the configmap if the certificates have changed
if [ ! "$(cat ../certificates/ca-bundle.crt)" = "$(kubectl get -n argocd configmaps certificates -o jsonpath='{.data}' 2>/dev/null | jq -r '."ca-bundle.crt"')" ] ||
  [ ! "$(cat ../docker-compose/docker/certificates/ca.crt)" = "$(kubectl get -n argocd configmaps certificates -o jsonpath='{.data}' 2>/dev/null | jq -r '."local-ca.crt"')" ]; then
  pod=$(kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-repo-server -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' 2>/dev/null)
  tmpfile=$(mktemp)
  if [ -n "$pod" ]; then
    refresh=1
  fi
  if ! grep -q 'BEGIN CERTIFICATE' "$tmpfile"; then
    cat /etc/ssl/certs/ca-certificates.crt >"$tmpfile"
  fi
  [ -f ../certificates/ca-bundle.crt ] && cat ../certificates/ca-bundle.crt >>"$tmpfile"
  [ -f ../docker-compose/docker/certificates/ca.crt ] && {
    echo "local ca"
    echo '====================================='
    cat ../docker-compose/docker/certificates/ca.crt
  } >>"$tmpfile"
  run_command kubectl create configmap -n argocd certificates --dry-run=client -o yaml --from-file=local-ca.crt=../docker-compose/docker/certificates/ca.crt --from-file=ca-bundle.crt=../certificates/ca-bundle.crt --from-file=ca-certificates.crt="$tmpfile" | kubectl apply -f -
  rm -f -- "$tmpfile"
fi

if ! kubectl get -n argocd deployments.apps/argocd-repo-server -o jsonpath='{.spec.template.spec.volumes}' | jq -r '.[].name' | grep -qFx certificates; then
  [ -n "$pod" ] || pod=$(kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-repo-server -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' 2>/dev/null)
  [ -n "$pod" ] || exit_error "Unable to get argocd repo server pod"

  run_command kubectl patch -n argocd deployment.apps/argocd-repo-server --type json -p '[{"op":"add","path":"/spec/template/spec/volumes/-","value":{"name":"certificates","configMap":{"name":"certificates"}}}]'
  run_command kubectl patch -n argocd deployment.apps/argocd-repo-server --type json -p '[{"op":"add","path":"/spec/template/spec/containers/0/volumeMounts/-","value":{"name":"certificates","mountPath":"/etc/ssl/certs/ca-certificates.crt","subPath":"ca-certificates.crt"}}]'
  refresh=1
fi

if [ "$refresh" -eq 1 ]; then
  run_command kubectl rollout restart -n argocd deployment argocd-repo-server
  run_command kubectl rollout status -n argocd deployment argocd-repo-server
fi

exit 0
