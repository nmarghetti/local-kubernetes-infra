#! /bin/bash

wait_container_running() {
  local container=$1
  local count=${2:-10}
  local interval=${3:-2}
  while [ ! "$(docker container inspect "$container" | jq .[0].State.Running)" = 'true' ] && [ "$count" -gt 0 ]; do
    log_debug "Waiting for container $container to be up and running"
    count=$((count - 1))
    sleep "$interval"
  done
  if [ "$count" -eq 0 ]; then
    return 1
  fi
}

compute_docker_compose_services_access() {
  touch ./docker-compose/docker-compose.env
  # shellcheck source=../docker-compose/docker-compose.env
  . ./docker-compose/docker-compose.env
  export PODINFO_PORT="${PODINFO_PORT:-9898}"

  . "$SCRIPTS"/setup_docker_registry.sh
  compute_docker_registry_access

  . "$SCRIPTS"/setup_helm.sh
  compute_helm_access
  . "$SCRIPTS"/build_helm.sh

  . "$SCRIPTS"/setup_portainer.sh
  compute_portainer_access

  . "$SCRIPTS"/setup_gitea.sh
  compute_gitea_access

  . "$SCRIPTS"/setup_dnsmasq.sh
  compute_dnsmasq_access

  . "$SCRIPTS"/setup_dkd.sh
}

setup_docker_compose_services() {
  compute_docker_compose_services_access

  # Retrieve system certificates
  ./certificates/retrieve_system_certificates.sh

  log_info "Starting docker compose services"
  dockerComposeFile=docker-compose-ssl.yaml
  [ "$use_ssl" -eq 0 ] && dockerComposeFile=docker-compose.yaml

  [ -z "$docker_services" ] && docker_services=$(yq .services -o json <./docker-compose/${dockerComposeFile} | jq -r '[keys[] | select(. | startswith("init-") | not)] | join(" ")')
  for service in $(yq .services -o json <./docker-compose/${dockerComposeFile} | jq -r '[keys[] | select(. | startswith("init-"))] | join(" ")'); do
    if key_in_array "$(echo "$service" | cut -d'-' -f2-)" "$docker_services" " " && ! key_in_array "$service" "$docker_services" " "; then
      docker_services="$docker_services $service"
    fi
  done

  if [ "$use_minikube" -eq 1 ]; then
    # Ensure to remove all docker container from minikube network if not right
    local minikube_network_id=
    docker network ls --format '{{.Name}}' | grep -qFx 'minikube' && minikube_network_id=$(docker network inspect minikube --format '{{.Id}}')
    # if minikube network exists but minikube is not up, ensure to remove minikube network and destroy minikube
    if [ -n "$minikube_network_id" ] && ! minikube ip &>/dev/null; then
      local container
      for container in $(docker network inspect minikube | jq -r '.[0].Containers | to_entries | .[].value.Name'); do
        run_command docker network disconnect minikube "$container" || exit_error "Unable to disconnect $container from minikube network"
      done
      run_command docker network rm minikube >/dev/null || exit_error "Unable to remove minikube network"
      run_command minikube delete
      minikube_network_id=
    fi
    for service in $docker_services; do
      service=$(yq .services -o json <./docker-compose/"${dockerComposeFile}" | jq -r '. | to_entries[] | select(.key=="'"$service"'") | .value.container_name')
      # if minikube network exist but the id is different, ensure to disconnect service from it
      if [ -n "$minikube_network_id" ]; then
        local service_minikube_network_id=
        service_minikube_network_id=$(docker inspect "$service" | jq -r '.[0].NetworkSettings.Networks | to_entries | .[] | select(.key == "minikube").value.NetworkID')
        if [ -n "$service_minikube_network_id" ] && [ ! "$service_minikube_network_id" = "$minikube_network_id" ]; then
          run_command docker network disconnect "minikube" "$service" || exit_error "Unable to disconnect $service from old minikube network ($service_minikube_network_id)"
        fi
      # if minikube network does not exist ensure to disconnect service from it
      else
        if docker inspect "$service" &>/dev/null && [ "$(docker inspect "$service" | jq -r '.[0].NetworkSettings.Networks | to_entries | .[] | select(.key == "minikube").key')" = "minikube" ]; then
          run_command docker network disconnect minikube "$service" || exit_error "Unable to disconnect $service from minikube network"
        fi
      fi
    done
  fi

  # shellcheck disable=SC2016
  envsubst '${REGISTRY_UI_PORT}' <"./docker-compose/docker/registry/config/config.template.yaml" >"./docker-compose/docker/registry/config/config.yaml"
  if key_in_array traefik "$docker_services" " "; then
    export REGISTRY_URL="http://registry.docker.localhost:${TRAEFIK_PORT}"
  fi
  [ ! -f './docker-compose/docker/dnsmasq/dnsmasq.conf' ] && cp './docker-compose/docker/dnsmasq/dnsmasq.template.conf' './docker-compose/docker/dnsmasq/dnsmasq.conf'

  if [ "$use_ssl" -eq 1 ] && ! openssl x509 -checkend 86400 -noout -in ./docker-compose/docker/certificates/ca.crt; then
    log_error "Certificates have expired, generating new ones with ./docker-compose/generate_certificates.sh"
    ./docker-compose/generate_certificates.sh
    run_command docker compose --env-file docker-compose/docker-compose.env -f ./docker-compose/${dockerComposeFile} stop
  fi

  # If traefik services is asked, ensure that kind is not already up and running (taking already port 80)
  # Also generate certificates
  if key_in_array traefik "$docker_services" " "; then
    if [ "$(docker inspect -f '{{.State.Status}}' kind-control-plane 2>/dev/null)" = "running" ]; then
      exit_error "Kind cluster is running, please stop it before being able to start traefik service as both are using port 80"
    fi
    if [ ! -f ./docker-compose/docker/traefik/config/certs/ca-certificates.crt ]; then
      ./docker-compose/docker/traefik/config/certs/generate.sh
    fi
  fi

  # If nginx services is asked, ensure to have some minikube certificates generated if not there yet
  if key_in_array traefik "$docker_services" " " && [ ! -f ./docker-compose/docker/nginx/certs/minikube_ca.crt ]; then
    CAROOT=./docker-compose/docker/nginx/certs mkcert -key-file "./docker-compose/docker/nginx/certs/minikube_client.key" -cert-file "./docker-compose/docker/nginx/certs/minikube_client.crt" "localhost"
    cp -f ./docker-compose/docker/nginx/certs/rootCA.pem ./docker-compose/docker/nginx/certs/minikube_ca.crt
  fi

  # shellcheck disable=SC2086
  run_command docker compose --env-file docker-compose/docker-compose.env -f ./docker-compose/${dockerComposeFile} up -d --build $docker_services || exit_error "Unable to start docker services"
  # if [ "$use_ssl" -eq 0 ] && [ "$(curl -sS -o "$tmp_file_output" -w "%{http_code}" "${registry_curl_args[@]}" "$registry_api/")" = '400' ] &&
  #   grep -q 'Client sent an HTTP request to an HTTPS server' "$tmp_file_output"; then
  #   run_command docker compose --env-file docker-compose/docker-compose.env -f ./docker-compose/${dockerComposeFile} restart || exit_error "Unable to restart docker services"
  # fi

  log_info "Waiting for docker services to be ready"
  # for container in $(yq .services -o json <./docker-compose/"${dockerComposeFile}" | jq -r '.[].container_name' | grep -vE '^init-'); do
  for container in $docker_services; do
    if [[ "$container" =~ ^init-.*$ ]]; then
      continue
    fi
    container_name=$(yq .services -o json <./docker-compose/"${dockerComposeFile}" | jq -r '. | to_entries[] | select(.key=="'"$container"'") | .value.container_name')
    wait_container_running "$container_name" 1 1 || exit_error "Container '$container_name is not up and running'"
  done

  # Check docker registry
  if key_in_array registry "$docker_services" " "; then
    wait_server_up 10 2 "${registry_curl_args[@]}" "$registry_api" || exit_error "docker registry from $registry_api not accessible"
  fi
  # Check helm registry
  if key_in_array helm "$docker_services" " "; then
    wait_server_up 10 2 "${helm_curl_args[@]}" "$helm_api" || exit_error "helm registry from $helm_api not accessible"
  fi
  # Check gitea
  if key_in_array gitea "$docker_services" " "; then
    wait_server_up 10 2 "$gitea_api" || exit_error "gitea from $gitea_api not accessible"
  fi
  # Check portainer
  if key_in_array portainer "$docker_services" " "; then
    wait_server_up 10 2 "-k" "$portainer_api" || exit_error "portainer from $portainer_api not accessible"
  fi
  # Check dnsmasq
  if key_in_array dnsmasq "$docker_services" " "; then
    netcat -q 2 -nzv 127.0.0.1 "$DNSMASQ_UI_PORT" || exit_error "Dnsmasq UI not accessible"
  fi

  log_info "Waiting for docker services initialization to be done"
  # for container in $(yq .services -o json <./docker-compose/"${dockerComposeFile}" | jq -r '.[].container_name' | grep -E '^init-'); do
  for container in $docker_services; do
    if [[ "$container" =~ ^init-.*$ ]]; then
      container_name=$(yq .services -o json <./docker-compose/"${dockerComposeFile}" | jq -r '. | to_entries[] | select(.key=="'"$container"'") | .value.container_name')
      if [ -n "$container_name" ]; then
        log_debug "Waiting for $container_name"
        [ "$(docker container wait "$container_name")" = "0" ] || exit_error "$container container failed, check logs with: docker logs $container_name"
      fi
    fi
  done

  # Ensure docker registry is setup
  if key_in_array registry "$docker_services" " "; then
    setup_docker_registry
  fi

  # Ensure helm registry is setup
  if key_in_array helm "$docker_services" " "; then
    setup_helm
  fi

  # Ensure portainer is setup
  if key_in_array portainer "$docker_services" " "; then
    setup_portainer
    [ "$(docker inspect init-portainer | jq -r '.[0].State | select(.Status == "exited" and .ExitCode == 0) | .ExitCode')" = "0" ] || exit_error "Portainer init container failed, check logs with: docker logs init-portainer"
  fi

  # Ensure gitea is setup
  if key_in_array gitea "$docker_services" " "; then
    setup_gitea
    [ "$(docker inspect init-gitea | jq -r '.[0].State | select(.Status == "exited" and .ExitCode == 0) | .ExitCode')" = "0" ] || exit_error "Gitea init container failed, check logs with: docker logs init-gitea"
    setup_git
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

  setup_docker_compose_services

  exit 0
}
