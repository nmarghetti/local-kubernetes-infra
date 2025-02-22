#! /bin/bash

compute_harness_access() {
  :
}

setup_harness() {
  compute_harness_access

  run_command helm upgrade -i helm-delegate --namespace harness-delegate-ng --create-namespace \
    harness-delegate/harness-delegate-ng \
    --set delegateName=helm-delegate \
    --set accountId="$harness_account_id" \
    --set delegateToken="$harness_delegate_token" \
    --set managerEndpoint=https://app.harness.io \
    --set delegateDockerImage="$harness_delegate_image" \
    --set replicas=1 \
    --set upgrader.enabled=true \
    --set tags="linux-amd64\,WSL-$(hostname)"
  # Wait until configmap is created
  log_debug "Waiting for harness-delegate-ng/helm-delegate to be created..."
  while ! kubectl get configmap -n harness-delegate-ng helm-delegate &>/dev/null; do
    sleep 1
  done
  local runner_url="http://${DOCKER_COMPOSE_HOST}:${HARNESS_DOCKER_RUNNER_PORT}"
  local current_runner_url
  current_runner_url="$(kubectl get configmap -n harness-delegate-ng helm-delegate -o jsonpath='{.data.RUNNER_URL}')"

  [[ -z "$current_runner_url" || ! "$current_runner_url" = "$runner_url" ]] &&
    run_command kubectl patch configmap -n harness-delegate-ng helm-delegate --type merge -p '{"data": {"RUNNER_URL": "http://'"${DOCKER_COMPOSE_HOST}"':'"${HARNESS_DOCKER_RUNNER_PORT}"'"}}' &&
    run_command kubectl rollout restart -n harness-delegate-ng deployment helm-delegate &&
    run_command kubectl rollout status -n harness-delegate-ng deployment helm-delegate

  log_info "Run the following command in a separated terminal to run Harness Docker Runner:"
  log_command "./scripts/start_harness_docker_runner.sh $HARNESS_DOCKER_RUNNER_PORT"
  log_command "curl http://localhost:${HARNESS_DOCKER_RUNNER_PORT}/healthz"

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
  # shellcheck source=./setup_cluster_access.sh
  . "$SCRIPTS"/setup_cluster_access.sh

  cd "$GIT_ROOT" || exit_error "Unable to go to git root folder"

  tmp_file_output=$(mktemp)
  trap 'rm -f -- $tmp_file_output' INT TERM HUP EXIT

  parse_args "$@"

  setup_harness

  exit 0
}
