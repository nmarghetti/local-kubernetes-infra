#! /bin/bash

setup_kubectl_user_context() {
  local cluster=
  local cluster_name=
  if [ "$use_minikube" -eq 1 ]; then
    cluster='minikube'
    cluster_name='minikube'
  elif [ "$use_kind" -eq 1 ]; then
    cluster='kind-kind'
    cluster_name='kind'
  else
    exit_error "You did not choose if you use minikube or kind (--kind | --minikube)"
  fi
  local cluster_context="${cluster}-${USER}"
  local user_name="${cluster_name}-$USER"
  # Generate certificate
  run_command openssl genrsa -out ./tmp/user.key 2048
  run_command openssl req -new -key ./tmp/user.key -out ./tmp/user.csr -subj "/CN=$USER"
  run_command_hide_nerr kubectl --context "$cluster" get certificatesigningrequests.certificates.k8s.io "$USER" >/dev/null && run_command kubectl --context "$cluster" delete certificatesigningrequests.certificates.k8s.io "$USER"
  cat <<EOF | kubectl --context "$cluster" apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: $USER
spec:
  request: $(base64 <./tmp/user.csr | tr -d '\n')
  signerName: kubernetes.io/kube-apiserver-client
  usages:
  - client auth
EOF
  run_command kubectl --context "$cluster" certificate approve "$USER"
  run_command kubectl wait --for=condition=Approved certificatesigningrequests "$USER" --timeout=10s
  run_command kubectl --context "$cluster" get csr "$USER" -o jsonpath='{.status.certificate}' | run_command_piped base64 --decode >./tmp/user.crt
  if [ "$(wc -l <./tmp/user.crt)" -eq 0 ]; then
    run_command sleep 5
    run_command kubectl --context "$cluster" get csr "$USER" -o jsonpath='{.status.certificate}' | run_command_piped base64 --decode >./tmp/user.crt
  fi
  if [ "$(wc -l <./tmp/user.crt)" -eq 0 ]; then
    log_warn "./tmp/user.crt is empty"
  fi

  # Create kubectl context <cluster>-user to connect with the user and the certificate
  run_command kubectl config set-credentials "$user_name" --embed-certs=true --client-certificate=./tmp/user.crt --client-key=./tmp/user.key
  run_command kubectl config set-context "$cluster_context" --cluster="$cluster" --user="$user_name" --namespace=default

  # Generate cluster info to add to Lens
  # run_command kubectl config --context "$cluster_context" view --minify --raw | run_command_piped yq '.users[0].user |= { "username": "'"$USER"'", "client-certificate-data": "'"$(base64 <./tmp/user.crt | tr -d '\n')"'", "client-key-data": "'"$(base64 <./tmp/user.key | tr -d '\n')"'" }' >./tmp/"${cluster_name}-user_kubeconfig.yaml"
  run_command kubectl config --context "$cluster_context" view --minify --raw | yq 'del(.current-context)' >./tmp/"${cluster_name}-user_kubeconfig.yaml"

  run_command kubectl --context "$cluster_context" create clusterrole list-namespaces --verb=get --verb=list --resource=namespaces --dry-run=client -o yaml | run_command_piped kubectl apply -f -
  run_command kubectl --context "$cluster_context" create clusterrolebinding list-namespaces-binding --clusterrole=list-namespaces --user="$USER" --dry-run=client -o yaml | run_command_piped kubectl apply -f -

  return 0
}

# (return 0 2>/dev/null) return true if the script is sourced
# [ "$(basename "$0")" = "setup_minikube.sh" ] return true if the script is run directly or sourced by a debugger
# Run if the script is not sourced or if it is sourced by a debugger so it keeps $0 as the script name
if [ "$(basename "$0")" = "setup_minikube.sh" ] || ! (return 0 2>/dev/null); then
  cd "$(dirname "$(readlink -f "$0")")" || {
    echo "Unable to go to parent folder of $0" >&2
    exit 1
  }

  SCRIPTS=$(git rev-parse --show-toplevel)/scripts
  # shellcheck source=./common.sh
  . "$SCRIPTS"/common.sh
  # shellcheck source=./setup_docker_compose_services.sh
  . "$SCRIPTS"/setup_docker_compose_services.sh

  cd "$GIT_ROOT" || exit_error "Unable to go to git root folder"

  parse_args "$@"

  setup_kubectl_user_context

  exit 0
fi
