#! /bin/bash

compute_minikube_access() {
  # Put default value in case minikube is not running yet
  HOST_IP=$(minikube ip) || HOST_IP="192.168.49.2"
  # DOCKER_COMPOSE_HOST=host.minikube.internal
  DOCKER_COMPOSE_HOST=host.local-cluster.internal
  CLUSTER_DOMAIN=minikube
  CLUSTER_CONTEXT=minikube
  export HOST_IP
  export DOCKER_COMPOSE_HOST
  export CLUSTER_DOMAIN
  export CLUSTER_CONTEXT
}

setup_minikube() {
  compute_minikube_access

  # Start the minikube cluster
  log_info "Starting minikube cluster"
  ./certificates/retrieve_system_certificates.sh
  ./certificates/copy_certificates_to_minikube.sh
  cp -f "$CERT_PATH/ca.crt" ~/.minikube/certs/local-ca.crt

  [ "$(minikube status -o json | jq .APIServer | xargs printf "%s")" = "Running" ] || run_command minikube start --embed-certs --insecure-registry="${DOCKER_COMPOSE_HOST}:${REGISTRY_PORT}" -v=5
  [ "$(minikube status -o json | jq .APIServer | xargs printf "%s")" = "Running" ] || exit_error "Unable to start local cluster"

  # Refresh minikube ip
  HOST_IP=$(minikube ip)
  export HOST_IP

  for addon in $minikube_addons; do
    run_command minikube addons enable "$addon"
  done
  run_command kubectl config use-context minikube || exit_error "Unable to use minikube kube context"

  # Make sure to have $DOCKER_COMPOSE_HOST resolving to localhost
  grep -q "$DOCKER_COMPOSE_HOST" /etc/hosts || sed -r -e "/localhost\$/a 127.0.0.1       $DOCKER_COMPOSE_HOST" /etc/hosts | sudo sponge /etc/hosts

  kubectl get -n kube-system configmaps coredns -o jsonpath='{.data}' | jq -r '.Corefile' >tmp/Corefile
  if ! grep "$DOCKER_COMPOSE_HOST" tmp/Corefile; then
    sed -i "/host.minikube.internal/ {
        p
        s/host.minikube.internal/$DOCKER_COMPOSE_HOST/
      }" tmp/Corefile
    run_command kubectl create configmap coredns -n kube-system --from-file=Corefile=tmp/Corefile --dry-run=client -o yaml | kubectl apply -f -
    run_command kubectl rollout restart -n kube-system deployment coredns
    run_command kubectl rollout status -n kube-system deployment coredns
  fi

  log_info "Checking cluser connectivity to $DOCKER_COMPOSE_HOST"
  run_command ssh-keyscan -t rsa "$HOST_IP" 2>/dev/null >>~/.ssh/known_hosts
  if ! ssh -o "IdentitiesOnly=yes" -o "StrictHostKeyChecking=no" -i ~/.minikube/machines/minikube/id_rsa docker@"$HOST_IP" "cat /etc/hosts" | grep -q "$DOCKER_COMPOSE_HOST"; then
    local minikube_internal_ip
    minikube_internal_ip="$(ssh -o "IdentitiesOnly=yes" -o "StrictHostKeyChecking=no" -i ~/.minikube/machines/minikube/id_rsa docker@"$HOST_IP" "cat /etc/hosts" | grep host.minikube.internal | head -1 | awk '{ print $1 }')"
    run_command ssh -o "IdentitiesOnly=yes" -o "StrictHostKeyChecking=no" -i ~/.minikube/machines/minikube/id_rsa docker@"$HOST_IP" "echo '$minikube_internal_ip    $DOCKER_COMPOSE_HOST' | sudo tee -a /etc/hosts >/dev/null"
  fi
  run_command ssh -o "IdentitiesOnly=yes" -o "StrictHostKeyChecking=no" -i ~/.minikube/machines/minikube/id_rsa docker@"$HOST_IP" "nc -vz $DOCKER_COMPOSE_HOST $PORTAINER_PORT" || exit_error "Local cluster is not able to connect to host"

  # Connect some services to minikube network
  for service in traefik dkd; do
    if [ "$(docker inspect -f '{{.State.Status}}' "$service" 2>/dev/null)" = "running" ]; then
      if [ ! "$(docker inspect "$service" | jq -r '.[0].NetworkSettings.Networks | to_entries | .[] | select(.key == "minikube").key')" = "minikube" ]; then
        run_command docker network connect minikube "$service" || exit_error "Unable to connect $service from minikube network"
      fi
    fi
  done
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
