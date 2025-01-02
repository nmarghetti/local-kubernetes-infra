#! /bin/bash

setup_argocd() {
  if [ "$use_minikube" -eq 0 ] && [ "$use_kind" -eq 0 ]; then
    exit_error "You did not choose if you use minikube or kind (--kind | --minikube)"
  fi

  if ! kubectl get namespaces argocd &>/dev/null; then
    # Install argocd
    run_command kubectl apply -k ./k8s/argocd/base/argocd

    # Wait for the secret to be available
    until kubectl get secret argocd-secret -n argocd &>/dev/null; do
      log_info "Waiting for argocd-secret to be available..."
      sleep 2
    done
    # Update the default admin password
    run_command kubectl -n argocd patch secret argocd-secret -p '{"stringData": {
      "admin.password": "'"$(argocd account bcrypt --password 'Y0NfZtbDAm9Yv3jz')"'",
      "admin.passwordMtime": "'"$(date +%FT%T%Z)"'"
    }}'

    # Restart argocd-server to apply the new password
    run_command kubectl rollout restart -n argocd deployment argocd-server
    run_command kubectl rollout status -n argocd deployment argocd-server
    run_command kubectl wait --for=condition=ready -n argocd --timeout=120s pod -l app.kubernetes.io/name=argocd-server
    run_command kubectl wait --for=condition=ready -n argocd --timeout=120s pod -l app.kubernetes.io/name=argocd-application-controller
    run_command kubectl wait --for=condition=ready -n argocd --timeout=120s pod -l app.kubernetes.io/name=argocd-applicationset-controller
    run_command kubectl wait --for=condition=ready -n argocd --timeout=120s pod -l app.kubernetes.io/name=argocd-notifications-controller
    run_command kubectl wait --for=condition=ready -n argocd --timeout=120s pod -l app.kubernetes.io/name=argocd-repo-server
  fi

  ARGOCD_OPTS=(
    --port-forward
    --port-forward-namespace argocd
    --plaintext)

  # Add the current cluster
  run_command argocd "${ARGOCD_OPTS[@]}" cluster add -y "$CLUSTER_CONTEXT"

  # Login to argocd
  run_command argocd "${ARGOCD_OPTS[@]}" login --insecure localhost --username admin --password 'Y0NfZtbDAm9Yv3jz'

  # Apply the certificates
  "$GIT_ROOT"/scripts/argocd_apply_certificates.sh

  # Add the git repository
  repos="$(argocd "${ARGOCD_OPTS[@]}" repo list | awk '{ print $2 }' | tail -n +2)"
  echo "$repos" | grep -qFx 'local_cluster' || run_command argocd "${ARGOCD_OPTS[@]}" repo add --type git --project default --name local_cluster ssh://git@host.local-cluster.internal:222/gitadmin/local_cluster.git --ssh-private-key-path "$HOME"/.ssh/id_rsa --insecure-ignore-host-key
  echo "$repos" | grep -qFx 'mychart' || run_command argocd "${ARGOCD_OPTS[@]}" repo add --type helm --project default --name mychart http://host.local-cluster.internal:8088/
  echo "$repos" | grep -qFx 'external-secrets-io' || run_command argocd "${ARGOCD_OPTS[@]}" repo add --type helm --project default --name external-secrets-io https://charts.external-secrets.io
  echo "$repos" | grep -qFx 'traefik' || run_command argocd "${ARGOCD_OPTS[@]}" repo add --type helm --project default --name traefik https://traefik.github.io/charts

  # Create the application
  argocd "${ARGOCD_OPTS[@]}" app list | grep -q cluster-local || run_command argocd "${ARGOCD_OPTS[@]}" app create cluster-local --repo ssh://git@host.local-cluster.internal:222/gitadmin/local_cluster.git --path "$argocd_path" --dest-server https://kubernetes.default.svc --dest-namespace argocd --auto-prune --sync-policy automatic --self-heal --sync-option Prune=true

  return 0
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
  # shellcheck source=./setup_gitea.sh
  . "$SCRIPTS"/setup_gitea.sh
  # shellcheck source=./setup_minikube.sh
  . "$SCRIPTS"/setup_minikube.sh
  # shellcheck source=./setup_kind.sh
  . "$SCRIPTS"/setup_kind.sh
  # shellcheck source=./setup_cluster_access.sh
  . "$SCRIPTS"/setup_cluster_access.sh

  cd "$GIT_ROOT" || exit_error "Unable to go to git root folder"

  parse_args "$@"

  compute_docker_compose_services_access
  compute_gitea_access
  compute_cluster_access
  setup_argocd

  exit 0
}
