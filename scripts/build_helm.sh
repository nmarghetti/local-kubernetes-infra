#! /bin/bash

build_helm() {
  local chart_name chart_version
  chart_name='generic-chart'
  chart_version=$(yq '.version' <"${GIT_ROOT}/helm/${chart_name}/Chart.yaml")
  log_info "Building local helm chart"
  helm plugin list | awk '{ print $1 }' | grep -qFx unittest || run_command_hide helm plugin install https://github.com/quintush/helm-unittest
  run_command_hide helm lint "${GIT_ROOT}/helm/${chart_name}" || exit_error "Helm lint failed"
  run_command_hide helm unittest "${GIT_ROOT}/helm/${chart_name}" -f '../tests/*_test.yaml' || exit_error "Helm unittest failed"
  run_command_hide helm package "${GIT_ROOT}/helm/${chart_name}" -d "$GIT_ROOT"/tmp || exit_error "Helm build failed"
  curl -sSf "${helm_curl_args[@]}" "$helm_api/$chart_name/$chart_version" &>/dev/null && run_command curl -sS -X DELETE -o /dev/null "${helm_curl_args[@]}" "$helm_api/$chart_name/$chart_version"
  run_command curl -sSf -o /dev/null "${helm_curl_args[@]}" --data-binary "@$GIT_ROOT/tmp/${chart_name}-${chart_version}.tgz" "$helm_api" || exit_error "Pushing helm failed"

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

  cd "$GIT_ROOT" || exit_error "Unable to go to git root folder"

  tmp_file_output=$(mktemp)
  trap 'rm -f -- $tmp_file_output' INT TERM HUP EXIT

  parse_args "$@"

  touch ./docker-compose/docker-compose.env
  # shellcheck source=../docker-compose/docker-compose.env
  . ./docker-compose/docker-compose.env

  # shellcheck source=./setup_helm.sh
  . "$SCRIPTS"/setup_helm.sh
  compute_helm_access

  build_helm

  exit 0
}
