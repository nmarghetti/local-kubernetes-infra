#! /bin/bash

compute_kind_access() {
  HOST_IP=$(ip addr show docker0 | awk '/inet / {print $2}' | cut -d/ -f1)
  DOCKER_COMPOSE_HOST=host.kind.internal
  DOCKER_COMPOSE_HOST=$HOST_IP
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
  if [ "$(docker inspect -f '{{.State.Status}}' traefik 2>/dev/null)" = "running" ]; then
    exit_error "Traefik service is running, please stop it being able to use kind as both are using port 80"
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
  # apiServerPort: 6443
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

  cd "$GIT_ROOT" || exit_error "Unable to go to git root folder"

  parse_args "$@"

  compute_docker_compose_services_access
  setup_kind

  exit 0
}
