#! /bin/bash

compute_kind_access() {
  HOST_IP=$(ip addr show docker0 | awk '/inet / {print $2}' | cut -d/ -f1)
  DOCKER_COMPOSE_HOST=host.local-cluster.internal
  CLUSTER_DOMAIN=localhost
  CLUSTER_CONTEXT=kind-kind
  export HOST_IP
  export DOCKER_COMPOSE_HOST
  export CLUSTER_DOMAIN
  export CLUSTER_CONTEXT
}

setup_kind() {
  compute_kind_access

  # Check that traefik services is not already up and running (taking already port 80)
  if [ "$(docker inspect -f '{{.State.Status}}' traefik 2>/dev/null)" = "running" ] && [ "$KIND_HTTP_PORT" = '80' ]; then
    exit_error "Traefik service is running, please stop it before being able to use kind as both are using port 80"
  fi

  # Start the kind cluster
  log_info "Starting kind cluster"

  kind_config=$(mktemp)
  cat <<EOM >"$kind_config"
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  # WARNING: It is _strongly_ recommended that you keep this the default
  # (127.0.0.1) for security reasons. However it is possible to change this.
  # apiServerAddress: "127.0.0.1"
  # By default the API server listens on a random open port.
  # You may choose a specific port but probably don't need to in most cases.
  # Using a random port makes it easier to spin up multiple clusters.
  apiServerPort: 32443
nodes:
- role: control-plane
  kubeadmConfigPatches:
    - |
      kind: InitConfiguration
      nodeRegistration:
        kubeletExtraArgs:
          node-labels: "ingress-ready=true"
  extraPortMappings:
    - containerPort: 80
      hostPort: ${KIND_HTTP_PORT:-80}
      protocol: TCP
    - containerPort: 443
      hostPort: ${KIND_HTTPS_PORT:-443}
      protocol: TCP
  extraMounts:
   - hostPath: $(pwd)/certificates
     containerPath: /usr/local/share/ca-certificates/corporate
- role: worker
  extraMounts:
  - hostPath: $(pwd)/certificates
    containerPath: /usr/local/share/ca-certificates/corporate
- role: worker
  extraMounts:
  - hostPath: $(pwd)/certificates
    containerPath: /usr/local/share/ca-certificates/corporate
- role: worker
  extraMounts:
  - hostPath: $(pwd)/certificates
    containerPath: /usr/local/share/ca-certificates/corporate
EOM
  if ! kind get clusters | grep -qFx kind; then
    run_command kind create cluster --config "$kind_config" || exit_error "Unable to create kind cluster"

    if key_in_array nginx "$docker_services" " "; then
      KIND_CONTROL_PLANE_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' kind-control-plane) || exit_error "Unable to get kind control plane IP"
      export KIND_CONTROL_PLANE_IP
      docker_compose_start_service nginx || exit_error "Unable to create kind cluster"
    fi

    # Add kind certificates to nginx service
    kubectl config view --minify --raw | yq 'del(.current-context)' >./tmp/kind_kubeconfig.yaml
    docker cp kind-control-plane:/etc/kubernetes/pki/ca.key ./tmp/kind_ca.key
    yq -r '.clusters[0].cluster.certificate-authority-data' <./tmp/kind_kubeconfig.yaml | base64 -d >./tmp/kind_ca.crt
    yq -r '.users[0].user.client-certificate-data' <./tmp/kind_kubeconfig.yaml | base64 -d >./tmp/kind_client.crt
    yq -r '.users[0].user.client-key-data' <./tmp/kind_kubeconfig.yaml | base64 -d >./tmp/kind_client.key
    yq '
      del(.clusters[0].cluster.certificate-authority-data) |
      del(.users[0].user) |
      .clusters[0].cluster.server |= "http://localhost:'"${TRAEFIK_PORT:-80}"'/nginx-kind-k8s/" |
      .clusters[0].name |= "kind_nginx" |
      .contexts[0].name |= "kind_nginx" |
      .contexts[0].context.cluster |= "kind_nginx" |
      .contexts[0].context.user |= "kind_nginx" |
      .users[0].name |= "kind_nginx"
      ' ./tmp/kind_kubeconfig.yaml >./tmp/kind_nginx_kubeconfig.yaml
    [ -z "${KUBECONFIG:-}" ] && KUBECONFIG=~/.kube/config:./tmp/kind_nginx_kubeconfig.yaml kubectl config view --flatten | sponge ~/.kube/config
    if [ ! -f ./docker-compose/docker/nginx/certs/kind_ca.crt ] || ! cmp --silent ./tmp/kind_ca.crt ./docker-compose/docker/nginx/certs/kind_ca.crt; then
      run_command cp -f ./tmp/kind_ca.crt ./docker-compose/docker/nginx/certs/kind_ca.crt
      run_command cp -f ./tmp/kind_client.crt ./docker-compose/docker/nginx/certs/kind_client.crt
      run_command cp -f ./tmp/kind_client.key ./docker-compose/docker/nginx/certs/kind_client.key
      if key_in_array nginx "$docker_services" " "; then
        run_command docker restart nginx >/dev/null || exit_error "Unable to restart nginx service"
      fi
    fi
    # Add kind certificates to traefik service
    if [ ! -f ./docker-compose/docker/traefik/config/certs/kind_ca.crt ] || ! openssl x509 -noout -issuer -in ./docker-compose/docker/traefik/config/certs/traefik-kind-server.crt | grep -qi kind; then
      ./docker-compose/docker/traefik/config/certs/generate.sh kind
      ./docker-compose/docker/traefik/config/certs/generate_ca.sh
      if key_in_array traefik "$docker_services" " "; then
        run_command docker restart traefik >/dev/null || exit_error "Unable to restart traefik service"
      fi
    fi

    # Create user context for kind cluster
    setup_kubectl_user_context
  fi
  for node in $(kind get nodes); do
    # Ensure it is started
    docker container start "$node" >/dev/null
    # Ensure it does not restart with host reboot
    docker update --restart=no "$node" >/dev/null
    # Ensure to have certificates
    run_command docker exec -it "$node" /bin/bash -c 'update-ca-certificates'
  done
  run_command kubectl config use-context "$(kind get kubeconfig | yq '.current-context')" || exit_error "Unable to use kind kube context"

  # Make sure to have $DOCKER_COMPOSE_HOST resolving to localhost
  grep -q "$DOCKER_COMPOSE_HOST" /etc/hosts || sed -r -e "/localhost\$/a 127.0.0.1       $DOCKER_COMPOSE_HOST" /etc/hosts | sudo sponge /etc/hosts

  kubectl get -n kube-system configmaps coredns -o jsonpath='{.data}' | jq -r '.Corefile' >tmp/Corefile
  if ! grep "$DOCKER_COMPOSE_HOST" tmp/Corefile; then
    sed -i '/prometheus/a\
    hosts {\
      '"$HOST_IP $DOCKER_COMPOSE_HOST"'\
      fallthrough\
    }' tmp/Corefile
    run_command kubectl create configmap coredns -n kube-system --from-file=Corefile=tmp/Corefile --dry-run=client -o yaml | kubectl apply -f -
    run_command kubectl rollout restart -n kube-system deployment coredns
    run_command kubectl rollout status -n kube-system deployment coredns
  fi

  log_info "Checking cluser connectivity from kind cluster to with host machine ($HOST_IP)"
  run_command docker exec -it kind-control-plane timeout 2 bash -c "</dev/tcp/${HOST_IP}/${PORTAINER_PORT}" || exit_error "Kind cluster is not able to connect to host"

  # Connect some services to kind network
  for service in nginx; do
    if [ "$(docker inspect -f '{{.State.Status}}' "$service" 2>/dev/null)" = "running" ]; then
      if [ ! "$(docker inspect "$service" | jq -r '.[0].NetworkSettings.Networks // {} | to_entries | .[] | select(.key == "kind").key')" = "kind" ]; then
        run_command docker network connect kind "$service" || exit_error "Unable to connect $service from kind network"
      fi
    fi
  done

  # Add kind CA to system certificates
  if [ ! -f /usr/local/share/ca-certificates/kind.crt ] || ! cmp --silent ./tmp/kind_ca.crt /usr/local/share/ca-certificates/kind.crt; then
    run_command sudo cp -f ./tmp/kind_ca.crt /usr/local/share/ca-certificates/kind.crt
    run_command sudo update-ca-certificates -f
  fi

  log_step "Run the following command to get kubeconfig file for kind cluster: kind export kubeconfig --kubeconfig ~/kind.kubeconfig"
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
  # shellcheck source=./setup_kubectl_user_context.sh
  . "$SCRIPTS"/setup_kubectl_user_context.sh

  cd "$GIT_ROOT" || exit_error "Unable to go to git root folder"

  parse_args "$@"

  compute_docker_compose_services_access
  setup_kind

  exit 0
}
