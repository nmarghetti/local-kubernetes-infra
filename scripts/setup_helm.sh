#! /bin/bash

compute_helm_access() {
  export HELM_PORT="${HELM_PORT:-8088}"

  helm_api="https://localhost:${HELM_PORT}/api/charts"
  helm_url="https://localhost:${HELM_PORT}/"
  helm_curl_args=(
    '--cacert' "$CERT_PATH/ca.crt"
    '--cert' "$CERT_PATH/helm-client_tls.crt"
    '--key' "$CERT_PATH/helm-client_tls.key"
  )
  [ "$use_ssl" -eq 0 ] && {
    helm_api="http://localhost:${HELM_PORT}/api/charts"
    helm_url="http://localhost:${HELM_PORT}/"
    helm_curl_args=()
  }
}

setup_helm() {
  compute_helm_access

  declare -A helm_charts_version=(
    ['external-secrets']=0.9.13
    ['eck-operator']=2.12.1
    ['eck-operator-crds']=2.12.1
    ['traefik']=31.1.1
    ['kubernetes-replicator']=2.11.0
    ['reloader']=1.1.0
  )
  declare -A helm_charts_url=(
    ['external-secrets']=https://github.com/external-secrets/external-secrets/releases/download/helm-chart-${helm_charts_version['external-secrets']}/external-secrets-${helm_charts_version['external-secrets']}.tgz
    ['eck-operator']=https://helm.elastic.co/helm/eck-operator/eck-operator-${helm_charts_version['eck-operator']}.tgz
    ['eck-operator-crds']=https://helm.elastic.co/helm/eck-operator-crds/eck-operator-crds-${helm_charts_version['eck-operator-crds']}.tgz
  )
  declare -A helm_charts_repo=(
    ['traefik']=https://traefik.github.io/charts
    ['kubernetes-replicator']=https://helm.mittwald.de
    ['reloader']=https://stakater.github.io/stakater-charts
  )
  declare -A helm_charts_name=(
    ['traefik']=traefik
    ['kubernetes-replicator']=kubernetes-replicator
    ['reloader']=reloader
  )

  log_info "Checking helm registry"
  run_command curl -sS -o "$tmp_file_output" "${helm_curl_args[@]}" "$helm_api" || exit_error "Unable to access helm api: $(cat "$tmp_file_output")"
  # If you need to delete the helm charts
  # for helm in "${!helm_charts_version[@]}"; do
  #   helm_version=${helm_charts_version[$helm]}
  #   rm -f "./tmp/${helm}-${helm_version}.tgz"
  #   run_command curl -X DELETE -sS "${helm_curl_args[@]}" "${helm_api}/${helm}/${helm_version}" >/dev/null
  # done
  # Ensure to add helm chart to our local helm repository
  local helm_chart
  local helm_version
  for helm_chart in "${!helm_charts_version[@]}"; do
    helm_version=${helm_charts_version[$helm_chart]}
    log_info "Ensure to have $helm_chart helm chart $helm_version to local repository"
    if [ ! "$(curl -sS "${helm_curl_args[@]}" "$helm_api" | jq '."'"$helm_chart"'"[] | select(.version == "'"$helm_version"'") | .version' 2>/dev/null | xargs printf "%s")" = "$helm_version" ]; then
      mkdir -p ./tmp
      if [ ! -f "./tmp/${helm_chart}-${helm_version}.tgz" ]; then
        if [[ -v helm_charts_repo[$helm_chart] ]]; then
          run_command helm repo add "$helm_chart" "${helm_charts_repo[$helm_chart]}" >/dev/null
          run_command helm pull "$helm_chart/${helm_charts_name[$helm_chart]}" --version "$helm_version" -d ./tmp >/dev/null
        else
          if ! run_command curl -sSL -o "./tmp/${helm_chart}-${helm_version}.tgz" "${helm_charts_url[$helm_chart]}"; then
            rm -f "./tmp/${helm_chart}-${helm_version}.tgz"
          fi
        fi
      fi
      [ -f "./tmp/${helm_chart}-${helm_version}.tgz" ] || exit_error "Unable to retrieve $helm_chart helm chart"
      run_command curl -sS "${helm_curl_args[@]}" --data-binary "@tmp/${helm_chart}-${helm_version}.tgz" "$helm_api" >/dev/null
      [ "$(curl -sS "${helm_curl_args[@]}" "$helm_api" | jq '."'"$helm_chart"'"[] | select(.version == "'"$helm_version"'") | .version' 2>/dev/null | xargs printf "%s")" = "$helm_version" ] || exit_error "Unable to have $helm_chart helm chart locally"
    fi
  done

  build_helm

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
  # shellcheck source=./build_helm.sh
  . "$SCRIPTS"/build_helm.sh

  cd "$GIT_ROOT" || exit_error "Unable to go to git root folder"

  tmp_file_output=$(mktemp)
  trap 'rm -f -- $tmp_file_output' INT TERM HUP EXIT

  parse_args "$@"

  touch ./docker-compose/docker-compose.env
  # shellcheck source=../docker-compose/docker-compose.env
  . ./docker-compose/docker-compose.env

  setup_helm

  exit 0
}
