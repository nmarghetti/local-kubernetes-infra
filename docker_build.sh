#! /bin/bash

cd "$(dirname "$(readlink -f "$0")")" || {
  echo "Unable to go to parent folder of $0" >&2
  exit 1
}
usage() {
  cat <<EOM
Usage: $0 [options]

Options:
    --debug-full <0|1>             : run the container in full debug mode or not (default: 1)
    --minikube <0|1>               : start minikube (default: 1)
    --minikube-dashboard           : start minikube dashboard
    --kind <0|1>                   : start kind (default: 0)
    --services <service[,service]> : run the specified service(s) amongs $(yq .services -o json <./docker-compose/docker-compose.yaml | jq -r '[keys[] | select(. | startswith("init-") | not)] | join(",")') (default: portainer,gitea,helm)
    --clean <service[,service]>    : remove the docker volume for the specified service(s) amongs minikube,registry,gitea,helm,portainer (default: none)
    --clean-all                    : remove the entire localarch docker volume and container
    --scenario <scenario>          : run the specified scenario amongs traefik-minikube, traefik-minikube-vault-helm (default: none)
    -h, --help                     : display this help
EOM
}

clean_all=0
START_MINIKUBE=1
START_MINIKUBE_DASHBOARD=0
START_KIND=0
DOCKER_SERVICES=portainer,gitea,helm
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
        minikube)
          START_MINIKUBE="${!OPTIND}"
          OPTIND=$((OPTIND + 1))
          ;;
        minikube-dashboard) START_MINIKUBE_DASHBOARD=1 ;;
        kind)
          START_KIND="${!OPTIND}"
          OPTIND=$((OPTIND + 1))
          ;;
        services)
          DOCKER_SERVICES="${!OPTIND}"
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

[ "$DEBUG_FULL" -eq 1 ] && set -x

export TRAEFIK_PORT=30000
export PORTAINER_PORT=30001
export GITEA_PORT=30002
export GITEA_SET_WEBHOOK=1
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
export DKD_PORT=30011
export TRAEFIK_DASHBOARD_PORT=30013
export MINIKUBE_DASHBOARD_PORT=30083
# shellcheck disable=SC2016
envsubst '${PORTAINER_PORT},${GITEA_PORT},${GITEA_SET_WEBHOOK},${REGISTRY_PORT},${REGISTRY_UI_PORT},${HELM_PORT},${DNSMASQ_PORT},${DNSMASQ_UI_PORT},${PODINFO_PORT},${WHOAMI_PORT},${NGINX_PORT},${DKD_PORT},${TRAEFIK_PORT},${TRAEFIK_DASHBOARD_PORT},${MINIKUBE_DASHBOARD_PORT}' <./docker_entrypoint.template.sh >./docker_entrypoint.sh

KIND_HTTP_PORT=30080
KIND_HTTPS_PORT=30443

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

kind_extra_args=()
if [ "$START_KIND" -eq 1 ]; then
  kind_extra_args=(
    --volume
    /sys/fs/cgroup:/sys/fs/cgroup:rw
    --security-opt
    seccomp=unconfined
  )
fi

if [ "$START_KIND" -eq 1 ]; then
  echo "Kind is not supported yet" >&2
  exit 1
fi

docker buildx build -t localarch --build-arg USERNAME="${USER:-USERNAME}" --build-arg WORKDIR="$PWD" --output type=docker . &&
  {
    docker container stop localarch >/dev/null 2>&1
    docker container rm localarch >/dev/null 2>&1
    docker run --privileged --cap-add=ALL \
      ${kind_extra_args[@]} \
      -e DEBUG_FULL="$DEBUG_FULL" \
      -e START_MINIKUBE="$START_MINIKUBE" \
      -e START_MINIKUBE_DASHBOARD="$START_MINIKUBE_DASHBOARD" \
      -e START_KIND="$START_KIND" \
      -e DOCKER_SERVICES="$DOCKER_SERVICES" \
      -e DOCKER_CLEAN_SERVICES="$DOCKER_CLEAN_SERVICES" \
      -e LOCAL_INFRA_SCENARIO="$LOCAL_INFRA_SCENARIO" \
      -e KIND_HTTP_PORT="$KIND_HTTP_PORT" \
      -e KIND_HTTPS_PORT="$KIND_HTTPS_PORT" \
      -dti --name localarch -v localarch_docker-data:/docker-data \
      -p 30771:8443 \
      -p "$PORTAINER_PORT:$PORTAINER_PORT" \
      -p "$GITEA_PORT:$GITEA_PORT" \
      -p "$REGISTRY_UI_PORT:$REGISTRY_UI_PORT" \
      -p "$DNSMASQ_PORT:$DNSMASQ_PORT" \
      -p "$DNSMASQ_UI_PORT:$DNSMASQ_UI_PORT" \
      -p "$PODINFO_PORT:$PODINFO_PORT" \
      -p "$WHOAMI_PORT:$WHOAMI_PORT" \
      -p "$NGINX_PORT:$NGINX_PORT" \
      -p "$DKD_PORT:$DKD_PORT" \
      -p "$TRAEFIK_PORT:$TRAEFIK_PORT" \
      -p "$TRAEFIK_DASHBOARD_PORT:$TRAEFIK_DASHBOARD_PORT" \
      -p "$MINIKUBE_DASHBOARD_PORT:$MINIKUBE_DASHBOARD_PORT" \
      -p "$KIND_HTTP_PORT:$KIND_HTTP_PORT" \
      -p "$KIND_HTTPS_PORT:$KIND_HTTPS_PORT" \
      -p 30050:30050 \
      -p 30051:30051 \
      -p 30052:30052 \
      -p 30053:30053 \
      -p 30054:30054 \
      -p 30055:30055 \
      -p 30056:30056 \
      -p 30057:30057 \
      -p 30058:30058 \
      -p 30059:30059 \
      localarch "$PWD"/docker_entrypoint.sh
    # -p "$REGISTRY_PORT:$REGISTRY_PORT" \
    # -p "$HELM_PORT:$HELM_PORT" \
  } || {
  echo "Unable to build localarch image" >&2
  exit 1
}

if [ "$START_MINIKUBE" -eq 1 ]; then
  cat <<EOM

Waiting for localarch container minikube kubernetes server to reply, check ./tmp/localarch.log for more details
Run the following command if you want to see the localarch container logs: docker logs -f localarch

EOM

  typeset -i cpt=0
  : >./tmp/localarch.log
  # wait 10min for minikube to be up and running
  while [ $cpt -lt 60 ] && ! docker exec -ti localarch sh -c 'curl https://127.0.0.1:32771/version' &>>./tmp/localarch.log; do
    printf '.'
    sleep 10
    cpt+=1
  done
  printf '\n\n'

  ! docker exec -ti localarch sh -c 'curl https://127.0.0.1:32771/version' &>/dev/null &&
    {
      echo "Unable to start localarch container" >&2
      exit 1
    }

  # Copy localarch minikube certificates to local system
  docker cp localarch:/usr/local/share/ca-certificates/minikube.crt /tmp/minikube-localarch.crt &&
    sudo mv -f /tmp/minikube-localarch.crt /usr/local/share/ca-certificates/minikube-localarch.crt &&
    sudo update-ca-certificates -f

  # Retrieve the minikube kubeconfig file
  docker exec -ti localarch cat tmp/minikube_kubeconfig.yaml | yq -o json | jq '.clusters[0].name |= "minikube_localarch" | .contexts[0].name |= "minikube_localarch" | .contexts[0].context.cluster |= "minikube_localarch" | .contexts[0].context.user |= "minikube_localarch" | .users[0].name |= "minikube_localarch"' | yq 'del(.current-context)' | yq -P >./tmp/minikube_localarch_kubeconfig.yaml
  yq -i 'del(.clusters[0].cluster.certificate-authority-data) | del(.users[0].user)' ./tmp/minikube_localarch_kubeconfig.yaml
  docker exec -ti localarch cat tmp/"minikube-${USER}_nginx_kubeconfig.yaml" | yq -o json | jq '.clusters[0].name |= "minikube_localarch-'"${USER}"'" | .contexts[0].name |= "minikube_localarch-'"${USER}"'" | .contexts[0].context.cluster |= "minikube_localarch-'"${USER}"'"' | yq 'del(.current-context)' | yq -P >./tmp/minikube_localarch-"${USER}"_kubeconfig.yaml

  cat <<EOM

You can check the minikube cluster version: docker exec -ti localarch sh -c 'curl https://127.0.0.1:32771/version'
You can use the following kubeconfig file to access the minikube cluster: ./tmp/minikube_localarch_kubeconfig.yaml
You should be able to access the following services:
  - Portainer: http://localhost:$PORTAINER_PORT
  - Links (if nginx and traefik are running): http://localhost:$NGINX_PORT

EOM
fi
