#! /bin/bash

wait_api_status() {
  local count=${1:-10}
  local interval=${2:-2}
  local status=${3:-200}
  shift 3
  local result=
  while true; do
    result="$(curl -s -o "$tmp_file_output" -w "%{http_code}" "$@")"
    if [ "$result" -ne "$status" ] && [ "$count" -gt 0 ]; then
      log_debug "Waiting for ${*: -1} to return status $status (instead of $result)"
      count=$((count - 1))
      sleep "$interval"
    else
      break
    fi
  done
  if [ "$count" -eq 0 ]; then
    cat "$tmp_file_output"
    return 1
  fi
}

compute_gitea_access() {
  export GITEA_PORT="${GITEA_PORT:-3000}"
  GITEA_DOCKER_HOST="${GITEA_DOCKER_HOST:-localhost}"
  GITEA_DOCKER_PORT="${GITEA_DOCKER_PORT:-$GITEA_PORT}"

  USE_SSL=${GITEA_USE_SSL:-${use_ssl:-0}}

  gitea_url="http://${GITEA_DOCKER_HOST}:$GITEA_DOCKER_PORT"
  gitea_exposed_url="http://localhost:${GITEA_PORT}"
  gitea_curl_args=(
    '--cacert' "$CERT_PATH/ca.crt"
    '--cert' "$CERT_PATH/gitea-client_tls.crt"
    '--key' "$CERT_PATH/gitea-client_tls.key"
  )

  gitea_api="$gitea_url/api/v1"

  gitea_admin="${GITEA__user__ADMIN_NAME:-}"
  gitea_admin_pass="${GITEA__user__ADMIN_PASSWORD:-}"
  gitea_admin_email="${GITEA__user__ADMIN_EMAIL:-}"
  if [ -z "$gitea_admin" ] || [ -z "$gitea_admin_pass" ]; then
    dockerComposeFile=docker-compose-ssl.yaml
    [ "$use_ssl" -eq 0 ] && dockerComposeFile=docker-compose.yaml
    gitea_admin=$(eval echo "$(yq -r '.services.init-gitea.environment.GITEA__user__ADMIN_NAME' -o json <./docker-compose/"$dockerComposeFile")")
    gitea_admin_pass=$(eval echo "$(yq -r '.services.init-gitea.environment.GITEA__user__ADMIN_PASSWORD' -o json <./docker-compose/"$dockerComposeFile")")
    gitea_admin_email=$(eval echo "$(yq -r '.services.init-gitea.environment.GITEA__user__ADMIN_EMAIL' -o json <./docker-compose/"$dockerComposeFile")")
  fi
  gitea_authorization="$(printf "%s:%s" "$gitea_admin" "$gitea_admin_pass" | base64)"
  gitea_curl_args=(
    '--header' "Authorization: Basic $gitea_authorization"
  )
  gitea_repo=local_cluster
}

setup_gitea() {
  compute_gitea_access

  log_info "Checking gitea"
  if [ "$(curl -sS -w "%{http_code}" -o /dev/null "${gitea_curl_args[@]}" "${gitea_api}"/user)" -eq 404 ]; then
    if [ "$(curl -s "$gitea_url" | grep -c '<title>Installation - Gitea')" -ne 0 ]; then
      log_step "Initializing gitea and creating admin user"
      run_command curl --request POST \
        -o /dev/null \
        --url "$gitea_url/" \
        --header 'Content-Type: application/x-www-form-urlencoded' \
        --data db_type=sqlite3 \
        --data db_host=localhost:3306 \
        --data db_user=root \
        --data db_passwd= \
        --data db_name=gitea \
        --data ssl_mode=disable \
        --data db_schema= \
        --data db_path=/data/gitea/gitea.db \
        --data 'app_name=Gitea:+Git+with+a+cup+of+tea' \
        --data repo_root_path=/data/git/repositories \
        --data lfs_root_path=/data/git/lfs \
        --data run_user=git \
        --data domain=localhost \
        --data ssh_port=22 \
        --data http_port=3000 \
        --data app_url="$gitea_url/" \
        --data log_root_path=/data/gitea/log \
        --data smtp_addr= \
        --data smtp_port= \
        --data smtp_from= \
        --data smtp_user= \
        --data smtp_passwd= \
        --data enable_federated_avatar=on \
        --data enable_open_id_sign_in=on \
        --data disable_registration=on \
        --data default_allow_create_organization=on \
        --data default_enable_timetracking=on \
        --data no_reply_address=noreply.localhost \
        --data password_algorithm=pbkdf2 \
        --data admin_name="$gitea_admin" \
        --data admin_email="$gitea_admin_email" \
        --data admin_passwd="$gitea_admin_pass" \
        --data admin_confirm_passwd="$gitea_admin_pass"
    fi
  fi
  wait_api_status 12 10 200 "${gitea_curl_args[@]}" "${gitea_api}/user" || exit_error "Unable to initialize gitea"
  if [ "$(curl -sS -w "%{http_code}" -o /dev/null "${gitea_curl_args[@]}" -H 'accept: application/json' "$gitea_api/repos/$gitea_admin/$gitea_repo")" -eq 404 ]; then
    log_step "Creating repository $gitea_repo"
    run_command curl -sS --request POST -o /dev/null "${gitea_curl_args[@]}" --header 'Content-Type: application/json' --url "$gitea_api"/user/repos \
      --data '{
      "default_branch": "main",
      "description": "Playground for local cluster",
      "name": "'"$gitea_repo"'",
      "private": true
    }'
  fi
  git remote | grep -qFx gitea || git remote add -m main gitea url
  curl -sS "${gitea_curl_args[@]}" -H 'accept: application/json' "$gitea_api/users/$gitea_admin/keys" -o $tmp_file_output
  # Check that if there is already an ssh key and it is not the same, let's remove it
  if [ "$(jq '. | length' <"$tmp_file_output")" -gt 0 ]; then
    if [ "$(jq -r '.[0].key' <"$tmp_file_output")" != "$(cat "$HOME"/.ssh/id_rsa.pub)" ]; then
      log_step "Removing old ssh key"
      key_id=$(jq -r '.[0].id' <"$tmp_file_output")
      code=$(run_command curl -sS --request DELETE -o "$tmp_file_output" -w "%{http_code}" "${gitea_curl_args[@]}" --header 'Content-Type: application/json' --url "$gitea_api/admin/users/$gitea_admin/keys/$key_id")
      [ "$code" -eq 204 ] || exit_error "$code: Unable to remove ssh key ($(cat "$tmp_file_output"))"
    fi
  fi
  # Add ssh key
  if [ "$(curl -sS "${gitea_curl_args[@]}" -H 'accept: application/json' "$gitea_api/users/$gitea_admin/keys" | jq '. | length')" -eq 0 ]; then
    log_step "Adding ssh key"
    code=$(run_command curl -sS --request POST -o "$tmp_file_output" -w "%{http_code}" "${gitea_curl_args[@]}" --header 'Content-Type: application/json' --url "$gitea_api/admin/users/$gitea_admin/keys" \
      --data '{
      "key": "'"$(cat "$HOME"/.ssh/id_rsa.pub)"'",
      "read_only": true,
      "title": "'"$gitea_admin"'"
    }')
    [ "$code" -eq 201 ] || exit_error "$code: Unable to add ssh key ($(cat "$tmp_file_output"))"
  fi
  if [ "$(curl -sS "${gitea_curl_args[@]}" -H 'accept: application/json' "$gitea_api/users/$gitea_admin/tokens" | jq '. | length')" -eq 0 ]; then
    log_step "Creating token"
    code=$(run_command curl -sS --request POST -o "$tmp_file_output" -w "%{http_code}" "${gitea_curl_args[@]}" --header 'Content-Type: application/json' --url "$gitea_api/users/$gitea_admin/tokens" \
      --data '{
      "name": "'"$gitea_admin"'",
      "scopes": [
        "write:repository"
      ]
    }')
    [ "$code" -eq 201 ] || exit_error "$code: Unable to create token ($(cat "$tmp_file_output"))"
    gitea_token=$(jq .sha1 "$tmp_file_output" | xargs printf "%s")
    docker exec -t gitea bash -c "echo '$gitea_token' >/data/token"
    log_step "Token created: $gitea_token"
  else
    gitea_token=$(docker exec -t gitea bash -c "cat /data/token | xargs printf '%s'")
    [ -z "$gitea_token" ] && gitea_token=$(git remote get-url gitea | sed -re 's#^https?://([^@]+)@.*$#\1#')
  fi
  [ -n "$gitea_token" ] || exit_error "Unable to get gitea token"
  log_step "Retrieved token: $gitea_token"
  log_step "Gitea is available at $gitea_url/$gitea_admin/$gitea_repo with admin user $gitea_admin and password $gitea_admin_pass"
  log_step "Gitea swagger is available at $gitea_api/swagger"
}

setup_git() {
  ssh-keyscan localhost 2>/dev/null >"$HOME/.ssh/known_hosts"
  git remote set-url gitea "ssh://git@localhost:222/$gitea_admin/${gitea_repo}.git"
  run_command git remote set-url gitea "$(echo "$gitea_url" | sed -re 's#(https?://)(.*)$#\1'"$gitea_token"'@\2#')/$gitea_admin/${gitea_repo}.git"
  run_command git push --quiet --force gitea main
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

  setup_gitea

  exit 0
}
