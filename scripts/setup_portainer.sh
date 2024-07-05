#! /bin/bash

check_curl_tmp_output() {
  local code=$1
  local message=$2
  if [ "$code" -ne 200 ]; then
    exit_error "$code: $message ($(cat "$tmp_file_output"))"
  fi
}

compute_portainer_access() {
  export PORTAINER_PORT="${PORTAINER_PORT:-9400}"
  PORTAINER_DOCKER_HOST="${PORTAINER_DOCKER_HOST:-localhost}"
  PORTAINER_DOCKER_PORT="${PORTAINER_DOCKER_PORT:-$PORTAINER_PORT}"

  USE_SSL=${USE_SSL:-${use_ssl:-0}}

  portainer_url="https://${PORTAINER_DOCKER_HOST}:${PORTAINER_DOCKER_PORT}"
  portainer_exposed_url="https://localhost:${PORTAINER_PORT}"
  portainer_curl_args=(
    '--cacert' "$CERT_PATH/ca.crt"
  )
  [ "$USE_SSL" -eq 0 ] && {
    portainer_url="http://${PORTAINER_DOCKER_HOST}:${PORTAINER_DOCKER_PORT}"
    portainer_exposed_url="http://localhost:${PORTAINER_PORT}"
    portainer_curl_args=()
  }
  portainer_api="$portainer_url/api"
}

setup_portainer() {
  compute_portainer_access

  portainer_password="${PORTAINER_ADMIN_PASSWORD:-}"
  if [ -z "$portainer_password" ]; then
    dockerComposeFile=docker-compose-ssl.yaml
    [ "$use_ssl" -eq 0 ] && dockerComposeFile=docker-compose.yaml
    portainer_password=$(eval echo "$(yq -r '.services.init-portainer.environment.PORTAINER_ADMIN_PASSWORD' -o json <./docker-compose/"$dockerComposeFile")")
  fi

  # If you need to reinitialize portainer:
  log_info "Checking portainer"
  code=$(curl "${portainer_curl_args[@]}" -sS -o "$tmp_file_output" -w "%{http_code}" --request POST --url "$portainer_api"/auth --header 'Content-Type: application/json' --data '{"Username": "admin","Password": "'"$portainer_password"'"}')
  [ "$code" -eq 0 ] && exit_error "$code: Unable to connect to portainer ($(cat "$tmp_file_output"))"
  if [ "$code" -eq 422 ]; then
    log_step "Creating portainer admin user"
    code=$(run_command curl "${portainer_curl_args[@]}" -sS -o "$tmp_file_output" -w "%{http_code}" --request POST --url "$portainer_api"/users/admin/init --header 'Content-Type: application/json' --data '{"Username": "admin","Password": "'"$portainer_password"'"}')
    if [ "$code" -eq 409 ]; then
      log_error "$code: Unable to create portainer admin user, it probably already exists but with another password ($(cat "$tmp_file_output"))"
    else
      [ "$code" -ne 200 ] && exit_error "$code: Unable to create portainer admin user ($(cat "$tmp_file_output"))"
    fi
    code=$(curl "${portainer_curl_args[@]}" -sS -o "$tmp_file_output" -w "%{http_code}" --request POST --url "$portainer_api"/auth --header 'Content-Type: application/json' --data '{"Username": "admin","Password": "'"$portainer_password"'"}')
  fi
  [ "$code" -ne 200 ] && exit_error "$code: Unable to authenticate to portainer ($(cat "$tmp_file_output"))"
  jwt=$(jq .jwt "$tmp_file_output" | xargs printf "%s")
  [ -n "$jwt" ] || exit_error "Unable to get portainer jwt token"

  code=$(curl "${portainer_curl_args[@]}" -sS -o "$tmp_file_output" -w "%{http_code}" --request GET --url "$portainer_api"/endpoints --header "Authorization: Bearer $jwt")
  check_curl_tmp_output "$code" "Unable to get portainer endpoints"
  env_id=$(jq '.[] | select (.Name == "local") | .Id' "$tmp_file_output")
  if [ -z "$env_id" ]; then
    log_step "Creating portainer local environment"
    code=$(run_command curl "${portainer_curl_args[@]}" -sS -o "$tmp_file_output" -w "%{http_code}" --request POST \
      --url "$portainer_api"/endpoints \
      --header "Authorization: Bearer $jwt" \
      --header 'Content-Type: multipart/form-data' \
      --form Name=local \
      --form EndpointCreationType=1 \
      --form PublicURL=localhost)
    check_curl_tmp_output "$code" "Unable to create portainer local environment"
    env_id=$(jq .Id "$tmp_file_output" | xargs printf "%s")
  fi
  [ -n "$env_id" ] || exit_error "Unable to get portainer local environment id"
  log_step "Portainer local environment is available at $portainer_exposed_url/#!/$env_id/docker/dashboard"
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

  setup_portainer

  exit 0
}
