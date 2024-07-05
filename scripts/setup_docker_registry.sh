#! /bin/bash

compute_docker_registry_access() {
  export REGISTRY_PORT="${REGISTRY_PORT:-5007}"
  export REGISTRY_UI_PORT="${REGISTRY_UI_PORT:-8087}"

  registry_api=https://localhost:${REGISTRY_PORT}/v2
  registry_curl_args=(
    '--cacert' "$CERT_PATH/ca.crt"
    # '--cert' "$CERT_PATH/registry-client_tls.crt"
    # '--key' "$CERT_PATH/registry-client_tls.key"
  )
  [ "$use_ssl" -eq 0 ] && {
    registry_api="http://localhost:${REGISTRY_PORT}/v2"
    registry_curl_args=()
  }
}

setup_docker_registry() {
  compute_docker_registry_access

  log_info "Checking docker registry"
  run_command curl -sS -o "$tmp_file_output" "${registry_curl_args[@]}" "$registry_api/" || exit_error "Unable to access registry api: $(cat "$tmp_file_output")"
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

  cd "$GIT_ROOT" || exit_error "Unable to go to git root folder"

  tmp_file_output=$(mktemp)
  trap 'rm -f -- $tmp_file_output' INT TERM HUP EXIT

  parse_args "$@"

  touch ./docker-compose/docker-compose.env
  # shellcheck source=../docker-compose/docker-compose.env
  . ./docker-compose/docker-compose.env

  setup_docker_registry

  exit 0
}
