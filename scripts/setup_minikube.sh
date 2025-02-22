#! /bin/bash

compute_minikube_access() {
  # Put default value in case minikube is not running yet
  HOST_IP=$(minikube ip) || HOST_IP="192.168.49.2"
  MINIKUBE_DASHBOARD_PORT=${MINIKUBE_DASHBOARD_PORT:-8083}
  # DOCKER_COMPOSE_HOST=host.minikube.internal
  DOCKER_COMPOSE_HOST=host.local-cluster.internal
  CLUSTER_DOMAIN=$minikube_domain
  CLUSTER_CONTEXT=minikube
  export HOST_IP
  export MINIKUBE_DASHBOARD_PORT
  export DOCKER_COMPOSE_HOST
  export CLUSTER_DOMAIN
  export CLUSTER_CONTEXT
}

start_minikube_dashboard() {
  local retry=${1:-1}

  local pids
  local minikube_pid=
  local kubectl_pid=

  pids=$(pgrep -d, minikube) && minikube_pid=$(ps -p "$pids" -o pid,cmd | grep -E "\--port( |=)$MINIKUBE_DASHBOARD_PORT" | awk '{ print $1 }')
  pids=$(pgrep -d, kubectl) && kubectl_pid=$(ps -p "$pids" -o pid,cmd | grep -E "\--port( |=)$MINIKUBE_DASHBOARD_PORT" | awk '{ print $1 }')

  if [ -n "$minikube_pid" ] && [ -n "$kubectl_pid" ]; then
    log_info "Minikube dashboard is already running"
    return 0
  fi

  [ "$retry" -eq 0 ] && log_info "Trying again to start minikube dashboard"
  local minikube_dashboard_pid
  : >./tmp/minikube_dashboard.log
  minikube dashboard --port="$MINIKUBE_DASHBOARD_PORT" --url=true &>"./tmp/minikube_dashboard.log" &
  minikube_dashboard_pid=$!
  local count=0
  while [ "$(wc -l <./tmp/minikube_dashboard.log)" -le 3 ] && [ "$count" -lt 5 ]; do
    sleep 1
    count=$((count + 1))
  done

  # Minikube dashboard is running, lets kill kubectl proxy and restart it on address 0.0.0.0
  if ps -p "$minikube_dashboard_pid" &>/dev/null; then
    pids=$(pgrep -d, kubectl) && ps -p "$pids" -o pid,cmd | grep -E "\--port( |=)$MINIKUBE_DASHBOARD_PORT" | awk '{ print $1 }' | xargs kill -9
    sleep 1
    kubectl --context minikube proxy --port="$MINIKUBE_DASHBOARD_PORT" --address=0.0.0.0 &
    sleep 2
    return 0
  fi

  # Minikube dashboard is running
  [ "$retry" -eq 0 ] && return 1

  # Try to kill the process and restart it
  pids=$(pgrep -d, minikube) && pids=$(ps -p "$pids" -o pid,cmd | grep -E "\--port( |=)$MINIKUBE_DASHBOARD_PORT" | awk '{ print $1 }')
  [ -n "$pids" ] && echo "Killing remaining minikube dashboard process" && run_command kill -9 "$pids"
  pids=$(pgrep -d, kubectl) && pids=$(ps -p "$pids" -o pid,cmd | grep -E "\--port( |=)$MINIKUBE_DASHBOARD_PORT" | awk '{ print $1 }')
  [ -n "$pids" ] && echo "Killing remaining dashboard kubectl port forward process" && run_command kill -9 "$pids"
  start_minikube_dashboard 0
  return $?
}

setup_minikube() {
  compute_minikube_access

  # Start the minikube cluster
  log_info "Starting minikube cluster"
  ./certificates/retrieve_system_certificates.sh
  ./certificates/copy_certificates_to_minikube.sh
  cp -f "$CERT_PATH/ca.crt" ~/.minikube/certs/local-ca.crt

  if [ ! "$(minikube status -o json | jq -r 'if type == "array" then . else [.] end | .[] | select(.Name == "minikube") | .APIServer')" = "Running" ]; then
    run_command minikube start --apiserver-port "$minikube_port" --nodes "$minikube_nodes" --embed-certs --insecure-registry="${DOCKER_COMPOSE_HOST}:${REGISTRY_PORT}" -v=5 || exit_error "Unable to start local cluster"

    # Add minikube certificates to nginx service
    kubectl config view --minify --raw | yq 'del(.current-context)' >./tmp/minikube_kubeconfig.yaml
    cp ~/.minikube/ca.key ./tmp/minikube_ca.key
    yq -r '.clusters[0].cluster.certificate-authority-data' <./tmp/minikube_kubeconfig.yaml | base64 -d >./tmp/minikube_ca.crt
    yq -r '.users[0].user.client-certificate-data' <./tmp/minikube_kubeconfig.yaml | base64 -d >./tmp/minikube_client.crt
    yq -r '.users[0].user.client-key-data' <./tmp/minikube_kubeconfig.yaml | base64 -d >./tmp/minikube_client.key
    yq '
      del(.clusters[0].cluster.certificate-authority-data) |
      del(.users[0].user) |
      .clusters[0].cluster.server |= "http://localhost:'"${TRAEFIK_PORT:-80}"'/nginx-minikube-k8s/" |
      .clusters[0].name |= "minikube_nginx" |
      .contexts[0].name |= "minikube_nginx" |
      .contexts[0].context.cluster |= "minikube_nginx" |
      .contexts[0].context.user |= "minikube_nginx" |
      .users[0].name |= "minikube_nginx"
      ' ./tmp/minikube_kubeconfig.yaml >./tmp/minikube_nginx_kubeconfig.yaml
    [ -z "${KUBECONFIG:-}" ] && KUBECONFIG=~/.kube/config:./tmp/minikube_nginx_kubeconfig.yaml kubectl config view --flatten | sponge ~/.kube/config
    if [ ! -f ./docker-compose/docker/nginx/certs/minikube_ca.crt ] || ! cmp --silent ./tmp/minikube_ca.crt ./docker-compose/docker/nginx/certs/minikube_ca.crt; then
      run_command cp -f ./tmp/minikube_ca.crt ./docker-compose/docker/nginx/certs/minikube_ca.crt
      run_command cp -f ./tmp/minikube_client.crt ./docker-compose/docker/nginx/certs/minikube_client.crt
      run_command cp -f ./tmp/minikube_client.key ./docker-compose/docker/nginx/certs/minikube_client.key
      if key_in_array nginx "$docker_services" " "; then
        run_command docker restart nginx >/dev/null || exit_error "Unable to restart nginx service"
      fi
    fi
    # Add minikube certificates to traefik service
    if [ ! -f ./docker-compose/docker/traefik/config/certs/minikube_ca.crt ] || ! openssl x509 -noout -issuer -in ./docker-compose/docker/traefik/config/certs/traefik-minikube-server.crt | grep -qi kind; then
      ./docker-compose/docker/traefik/config/certs/generate.sh minikube
      ./docker-compose/docker/traefik/config/certs/generate_ca.sh
      if key_in_array traefik "$docker_services" " "; then
        run_command docker restart traefik >/dev/null || exit_error "Unable to restart traefik service"
      fi
    fi

    # Create user context for minikube cluster
    setup_kubectl_user_context
  fi
  [ "$(minikube status -o json | jq -r 'if type == "array" then . else [.] end | .[] | select(.Name == "minikube") | .APIServer')" = "Running" ] || exit_error "Unable to start local cluster"

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
  for service in traefik nginx dkd; do
    if [ "$(docker inspect -f '{{.State.Status}}' "$service" 2>/dev/null)" = "running" ]; then
      if [ ! "$(docker inspect "$service" | jq -r '.[0].NetworkSettings.Networks // {} | to_entries | .[] | select(.key == "minikube").key')" = "minikube" ]; then
        run_command docker network connect minikube "$service" || exit_error "Unable to connect $service from minikube network"
      fi
    fi
  done

  # Setup minikube dashboard
  if [ "$start_minikube_dashboard" -eq 1 ]; then
    log_info "Starting minikube dashboard"
    start_minikube_dashboard || exit_error "Unable to start minikube dashboard, check with: ps -ae -o pid,cmd | grep -E '(minikube|kubectl)' | grep '${MINIKUBE_DASHBOARD_PORT}'"
    log_step "Minikube dashboard accessible via http://localhost:${MINIKUBE_DASHBOARD_PORT}/api/v1/namespaces/kubernetes-dashboard/services/http:kubernetes-dashboard:/proxy/#/workloads?namespace=_all"
  fi

  # Add minikube CA to system certificates
  if [ ! -f /usr/local/share/ca-certificates/minikube.crt ] || ! cmp --silent ~/.minikube/ca.crt /usr/local/share/ca-certificates/minikube.crt; then
    run_command sudo cp -f ~/.minikube/ca.crt /usr/local/share/ca-certificates/minikube.crt
    run_command sudo update-ca-certificates -f
  fi

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
  # shellcheck source=./setup_kubectl_user_context.sh
  . "$SCRIPTS"/setup_kubectl_user_context.sh

  cd "$GIT_ROOT" || exit_error "Unable to go to git root folder"

  parse_args "$@"

  compute_docker_compose_services_access
  setup_minikube

  exit 0
fi
