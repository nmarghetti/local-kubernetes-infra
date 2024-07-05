#! /bin/bash

compute_dkd_access() {
  . "$SCRIPTS"/setup_docker_registry.sh
  compute_docker_registry_access
}

setup_dkd() {
  compute_dkd_access

  # Ensure docker registry is up and running
  wait_server_up 10 2 "${registry_curl_args[@]}" "$registry_api" || exit_error "docker registry from $registry_api not accessible"

  log_info "Ensure to have dkd image built"
  if [ ! "$(run_command curl -sS "${registry_curl_args[@]}" "$registry_api/_catalog" | jq '.repositories | to_entries[] | select(.value == "dkd") | .value' | xargs -r printf)" = "dkd" ] ||
    [ ! "$(run_command curl -sS "${registry_curl_args[@]}" "$registry_api/dkd/tags/list" | jq 'any(.tags[]; . == "latest")')" = "true" ]; then
    ./dkd/docker-build.sh
  fi
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

  setup_dkd

  exit 0
}
