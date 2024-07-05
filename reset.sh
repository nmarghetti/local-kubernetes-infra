#! /bin/sh

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info() {
  printf "${GREEN}%s${NC}\n" "$@" >&2
}

log_step() {
  printf "${YELLOW}%s${NC}\n" "$@" >&2
}

log_command() {
  printf "${CYAN}%s${NC}\n" "$@" >&2
}

log_error() {
  printf "${RED}%s${NC}\n" "$@" >&2
}

exit_error() {
  log_error "$@" >&2
  exit 1
}

cd "$(dirname "$(readlink -f "$0")")" || exit_error "Unable to go into script folder"

DOCKER_COMPOSE_NAME="${DOCKER_COMPOSE_NAME:-local-services}"

# minikube
minikube delete
# kind
kind delete cluster
# docker build container
docker container stop localarch
docker container rm localarch
docker volume rm localarch_docker-data
# docker compose
docker compose --env-file docker-compose/docker-compose.env -f ./docker-compose/docker-compose.yaml stop
docker compose --env-file docker-compose/docker-compose.env -f ./docker-compose/docker-compose.yaml rm -f
for volume in $(yq '.volumes' -o json <./docker-compose/docker-compose.yaml | jq -r 'keys[]'); do
  docker volume rm "${DOCKER_COMPOSE_NAME}_${volume}"
done
# docker container stop portainer && docker container rm portainer && docker container rm init-portainer && docker volume rm local-services_portainer
# docker container stop gitea && docker container rm gitea && docker container rm init-gitea && docker volume rm local-services_gitea
