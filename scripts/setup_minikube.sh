#! /bin/bash

compute_minikube_access() {
  HOST_IP=$(minikube ip)
  DOCKER_COMPOSE_HOST=host.minikube.internal
  CLUSTER_DOMAIN=minikube
  export HOST_IP
  export DOCKER_COMPOSE_HOST
  export CLUSTER_DOMAIN
}

setup_minikube() {
  # Start the minikube cluster
  log_info "Starting minikube cluster"
  ./certificates/retrieve_system_certificates.sh
  ./certificates/copy_certificates_to_minikube.sh
  cp -f "$CERT_PATH/ca.crt" ~/.minikube/certs/local-ca.crt

  [ "$(minikube status -o json | jq .APIServer | xargs printf "%s")" = "Running" ] || run_command minikube start --embed-certs --insecure-registry=host.minikube.internal:5007 -v=5
  [ "$(minikube status -o json | jq .APIServer | xargs printf "%s")" = "Running" ] || exit_error "Unable to start local cluster"
  for addon in $minikube_addons; do
    run_command minikube addons enable "$addon"
  done
  run_command kubectl config use-context minikube || exit_error "Unable to use minikube kube context"

  # Make sure to have host.minikube.internal resolving to localhost
  grep -q 'host.minikube.internal' /etc/hosts || sed -r -e "/localhost\$/a 127.0.0.1       host.minikube.internal" /etc/hosts | sudo sponge /etc/hosts

  log_info "Checking cluser connectivity to host.minikube.internal"
  run_command ssh-keyscan -t rsa "$(minikube ip)" 2>/dev/null >>~/.ssh/known_hosts
  run_command ssh -o "IdentitiesOnly=yes" -o "StrictHostKeyChecking=no" -i ~/.minikube/machines/minikube/id_rsa docker@"$(minikube ip)" "nc -vz host.minikube.internal $PORTAINER_PORT" || exit_error "Local cluster is not able to connect to host"

  compute_minikube_access
}

# If the script is not being sourced, run the setup
(return 0 2>/dev/null) || {
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

  compute_docker_compose_services_access
  setup_minikube

  exit 0
}
