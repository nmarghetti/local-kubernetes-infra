#! /bin/bash

cd "$(dirname "$(readlink -f "$0")")" || {
  echo "Unable to go to parent folder of $0" >&2
  exit 1
}

. ./common.sh

refresh=0
pod=

[ "$FULL_DEBUG" = '1' ] && set -eoxu pipefail

if ! kubectl get namespaces flux-system &>/dev/null; then
  run_command kubectl create namespace flux-system || exit_error "Unable to create namespace flux-system"
fi

# Refresh the configmap if the certificates have changed
if [ ! "$(cat ../certificates/ca-bundle.crt)" = "$(kubectl get -n flux-system configmaps certificates -o jsonpath='{.data}' 2>/dev/null | jq -r '."ca-bundle.crt"')" ] ||
  [ ! "$(cat ../docker-compose/docker/certificates/ca.crt)" = "$(kubectl get -n flux-system configmaps certificates -o jsonpath='{.data}' 2>/dev/null | jq -r '."local-ca.crt"')" ]; then
  pod=$(kubectl get pods -n flux-system -l app=source-controller -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' 2>/dev/null)
  tmpfile=$(mktemp)
  if [ -n "$pod" ]; then
    refresh=1
    # kubectl exec -t -n flux-system "$pod" -- cat /etc/ssl/certs/ca-certificates.crt >"$tmpfile"
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
  # Ensure that the config map does not exist otherwise its content is too big for its annotation
  kubectl get configmap -n flux-system certificates &>/dev/null && kubectl delete configmap -n flux-system certificates &>/dev/null
  run_command kubectl create configmap -n flux-system certificates --from-file=local-ca.crt=../docker-compose/docker/certificates/ca.crt --from-file=ca-bundle.crt=../certificates/ca-bundle.crt --from-file=ca-certificates.crt="$tmpfile"
  rm -f -- "$tmpfile"
fi

# if ! kubectl get -n flux-system deployments.apps/source-controller -o jsonpath='{.spec.template.spec.volumes}' | jq -r '.[].name' | grep -qFx certificates; then
#   [ -n "$pod" ] || pod=$(kubectl get pods -n flux-system -l app=source-controller -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}')
#   [ -n "$pod" ] || exit_error "Unable to get flux source-controller pod"

#   run_command kubectl patch -n flux-system deployment.apps/source-controller --type json -p '[{"op":"add","path":"/spec/template/spec/volumes/-","value":{"name":"certificates","configMap":{"name":"certificates"}}}]'
#   run_command kubectl patch -n flux-system deployment.apps/source-controller --type json -p '[{"op":"add","path":"/spec/template/spec/containers/0/volumeMounts/-","value":{"name":"certificates","mountPath":"/etc/ssl/certs/ca-certificates.crt","subPath":"ca-certificates.crt"}}]'
# fi

[ "$refresh" -eq 1 ] && run_command kubectl rollout restart -n flux-system deployment.apps/source-controller

exit 0
