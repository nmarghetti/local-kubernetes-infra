#! /bin/bash

cd "$(dirname "$(readlink -f "$0")")" || {
  echo "Unable to go to parent folder of $0" >&2
  exit 1
}
usage() {
  cat <<EOM
Usage: $0 [options]

Options:
    --debug-full <0|1>          : run the container in full debug mode or not (default: 1)
    --clean <service[,service]> : remove the docker volume for the specified service(s) amongs minikube,registry,gitea,helm,portainer (default: none)
    --clean-all                 : remove the entire localarch docker volume and container
    --scenario <scenario>       : run the specified scenario amongs traefik-minikube, traefik-minikube-vault-helm (default: none)
    -h, --help                  : display this help
EOM
}

clean_all=0
DOCKER_CLEAN_SERVICES=
LOCAL_INFRA_SCENARIO=
DEBUG_FULL=1
OPTIND=1
while getopts "h-:" opt; do
  case "$opt" in
    h)
      usage
      exit 0
      ;;
    -)
      case "$OPTARG" in
        debug-full)
          DEBUG_FULL="${!OPTIND}"
          OPTIND=$((OPTIND + 1))
          ;;
        clean)
          for service in $(echo "${!OPTIND}" | tr ',' ' '); do
            case "$service" in
              minikube | registry | gitea | helm | portainer)
                :
                ;;
              *)
                echo "Unknown service $service"
                usage
                exit 1
                ;;
            esac
          done
          DOCKER_CLEAN_SERVICES="${!OPTIND}"
          OPTIND=$((OPTIND + 1))
          ;;
        scenario)
          LOCAL_INFRA_SCENARIO="${!OPTIND}"
          OPTIND=$((OPTIND + 1))
          ;;
        clean-all) clean_all=1 ;;
        *)
          echo "Unknow option $OPTARG"
          usage
          exit 1
          ;;
      esac
      ;;
    \? | *)
      usage
      exit 1
      ;;
  esac
done
shift $((OPTIND - 1))
[ $# -ne 0 ] && {
  echo "Error: No argument accepted." >&2
  usage
  exit 1
}

export PORTAINER_PORT=30001
export GITEA_PORT=30002
# Do not customize REGISTRY_PORT, it is not supported yet
# export REGISTRY_PORT=3003
export REGISTRY_PORT=5007
export REGISTRY_UI_PORT=30004
# Do not customize HELM_PORT, it is not supported yet
# export HELM_PORT=30005
export HELM_PORT=8088
export DNSMASQ_PORT=30006
export DNSMASQ_UI_PORT=30007
export PODINFO_PORT=30008
export WHOAMI_PORT=30009
export NGINX_PORT=30010
# shellcheck disable=SC2016
envsubst '${PORTAINER_PORT},${GITEA_PORT},${REGISTRY_PORT},${REGISTRY_UI_PORT},${HELM_PORT},${DNSMASQ_PORT},${DNSMASQ_UI_PORT},${PODINFO_PORT},${WHOAMI_PORT},${NGINX_PORT}' <./docker_entrypoint.template.sh >./docker_entrypoint.sh

# Retrieve system certificates if none are present yet
find ./certificates -name "*.crt" ! -name "ca-bundle.crt" | wc -l | grep -qwv '0' && [ ! -f ./certificates/ca-bundle.crt ] &&
  ./certificates/retrieve_system_certificates.sh

#  Create a volume to save docker data, clean it first if requested
if [ "$clean_all" -eq 1 ]; then
  docker container stop localarch >/dev/null 2>&1
  docker container rm localarch >/dev/null 2>&1
  docker volume rm localarch_docker-data >/dev/null 2>&1
fi
! docker volume ls -q | grep -qw localarch_docker-data && docker volume create localarch_docker-data >/dev/null

docker buildx build -t localarch --output type=docker . &&
  {
    docker container stop localarch >/dev/null 2>&1
    docker container rm localarch >/dev/null 2>&1
    docker run --privileged --cap-add=ALL -e DEBUG_FULL="$DEBUG_FULL" -e DOCKER_CLEAN_SERVICES="$DOCKER_CLEAN_SERVICES" -e LOCAL_INFRA_SCENARIO="$LOCAL_INFRA_SCENARIO" -e KIND_HTTP_PORT=30080 -e KIND_HTTPS_PORT=30443 -dti --name localarch -v localarch_docker-data:/docker-data \
      -p "$PORTAINER_PORT:$PORTAINER_PORT" \
      -p "$GITEA_PORT:$GITEA_PORT" \
      -p "$REGISTRY_UI_PORT:$REGISTRY_UI_PORT" \
      -p "$DNSMASQ_PORT:$DNSMASQ_PORT" \
      -p "$DNSMASQ_UI_PORT:$DNSMASQ_UI_PORT" \
      -p "$PODINFO_PORT:$PODINFO_PORT" \
      -p "$WHOAMI_PORT:$WHOAMI_PORT" \
      -p "$NGINX_PORT:$NGINX_PORT" \
      localarch
    # -p "$REGISTRY_PORT:$REGISTRY_PORT" \
    # -p "$HELM_PORT:$HELM_PORT" \
  } && cat <<EOM
- Portainer: https://localhost:$PORTAINER_PORT
EOM

# for file in $(docker exec -ti localarch bash -c 'docker exec -ti minikube bash -c "ls -1 /var/lib/minikube/certs/*ca.crt"'); do
#   file=$(echo "$file" | sed -re 's/[[:space:]]*([^[:space:]].*[^[:space:]])[[:space:]]*$/\1/')
#   docker exec -ti localarch bash -c "docker exec -ti minikube bash -c 'cat $file'" | sudo tee /usr/local/share/ca-certificates/minikube-"$(basename "$file")" >/dev/null
# done && sudo update-ca-certificates -f
