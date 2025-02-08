#! /bin/bash

export CERT_PATH=./docker-compose/docker/certificates

GIT_ROOT=
if type git >/dev/null 2>&1; then
  GIT_ROOT="$(git rev-parse --show-toplevel)"
  [ -n "$GIT_ROOT" ] || exit_error "Unable to retrieve the root of the git repository"
  # shellcheck source=../docker-compose/docker-compose.env
  [ -f "$GIT_ROOT"/docker-compose/docker-compose.env ] && . "$GIT_ROOT"/docker-compose/docker-compose.env
fi

log_file=
if [ -n "$GIT_ROOT" ]; then
  log_file="$GIT_ROOT"/scripts/utils/log.sh
elif [[ -v "${BASH_SOURCE[0]}" ]]; then
  log_file="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"/utils/log.sh
fi
if [ ! -f "$log_file" ]; then
  echo "Unable to find log.sh" >&2
  exit 1
fi
# shellcheck source=./utils/log.sh
. "$log_file"
unset log_file

usage() {
  cat <<EOM >&2
Usage: $0 [options]

Options:
  -k, --no-ssl                            : do not use TLS (default)
  -s, --use-ssl                           : use TLS
  -d, --debug                             : debug mode (default)
      --debug-full                        : debug bash
    --minikube                            : setup minikube
    --minikube-addons <addon [addon...]>  : enable minikube addons eg. ingress,ingress-dns
    --minikube-dns                        : setup dnsmasq to resolve minikube domain
    --minikube-domain <domain>            : set minikube domain (default: minikube)
    --minikube-dashboard                  : start minikube dashboard
    --kind                                : setup kind
    --kind-port <port>                    : port on which kind listens for http (defaut 8880)
    --kind-tls-port <port>                : port on which kind listens for https (defaut 8843)
    --kind-podinfo                        : add podinfo in kind cluster
    --docker-services <service[,service]> : select docker services, comma separated, to setup amongs $(yq .services -o json <./docker-compose/docker-compose.yaml | jq -r '[keys[] | select(. | startswith("init-") | not)] | join(",")') (default all)
    --traefik-log <level>                 : set traefik log level amongs TRACE,DEBUG,INFO,WARN,ERROR,FATAL,PANIC (default: INFO)
    --nginx-log <level>                   : set nginx log level amongs debug,info,notice,warn,error,crit,alert,emerg (default: notice)
    --dkd                                 : setup dkd image
    --gitea-webhook                       : setup gitea webhook to notify flux
    --flux-path <path>                    : select flux path amongs $(find ./k8s/flux-playground -maxdepth 2 -name "flux-system" | tr '\n' ',' | head -c -1)
    --flux-boostrap                       : bootstrap flux instead of creating credentials and just applying the manifests
    --flux-auth <auth>                    : select auth type for flux amongs ssh, token, login (default: ssh)
    --flux-image-automation               : add flux component for image automation
    --flux-local-helm                     : use local helm registry (default: false)
    --argocd-path <path>                  : select argocd path amongs $(find ./k8s/argocd-playground -maxdepth 2 -name "argocd" | tr '\n' ',' | head -c -1)
  -q                                      : quiet mode, print less information
  -h                                      : display this help

EOM
}

key_in_array() {
  local split=$3
  [ -z "$split" ] && split=','
  echo "$2" | tr "$split" '\n' | grep -q -x -F -e "$1"
}

wait_server_up() {
  local count=${1:-10}
  local interval=${2:-2}
  shift 2
  printf "" >"$tmp_file_output"
  # shellcheck disable=SC2016
  while ! timeout 1 bash -c '[ "$(curl -s -o "'"$tmp_file_output"'" -w "%{http_code}" '"$*"')" -ne 0 ]' && [ "$count" -gt 0 ]; do
    log_debug "Waiting for ${*: -1} to be accesible"
    count=$((count - 1))
    sleep "$interval"
  done
  if [ "$count" -eq 0 ]; then
    echo "curl -sS $*"
    cat "$tmp_file_output"
    return 1
  fi
}

parse_args() {
  use_ssl=0
  use_minikube=0
  start_minikube_dashboard=0
  use_kind=0
  KIND_HTTP_PORT=${KIND_HTTP_PORT:-8800}
  KIND_HTTPS_PORT=${KIND_HTTPS_PORT:-8843}
  setup_kind_podinfo=0
  use_dkd=0
  use_flux=0
  flux_path=""
  flux_auth="ssh"
  flux_image_automation=0
  flux_local_helm=0
  flux_bootstrap=0
  GITEA_SET_WEBHOOK=0
  use_argocd=0
  argocd_path=""
  use_dnsmasq=0
  minikube_addons=
  minikube_domain=minikube
  docker_services=portainer
  NGINX_LOG_LEVEL=info
  TRAEFIK_LOG_LEVEL=info
  # reset getopts - check https://man.cx/getopts(1)
  OPTIND=1
  while getopts "hksqv-:" opt; do
    case "$opt" in
      k) use_ssl=0 ;;
      s) use_ssl=1 ;;
      q)
        export DEBUG=0
        ;;
      h)
        usage
        exit 0
        ;;
      -)
        case "$OPTARG" in
          debug-full)
            set -eoxu pipefail
            export FULL_DEBUG=1
            ;;
          no-ssl) use_ssl=0 ;;
          use-ssl) use_ssl=1 ;;
          minikube) use_minikube=1 ;;
          minikube-dashboard) start_minikube_dashboard=1 ;;
          kind) use_kind=1 ;;
          kind-port)
            KIND_HTTP_PORT="${!OPTIND}"
            OPTIND=$((OPTIND + 1))
            ;;
          kind-tls-port)
            KIND_HTTPS_PORT="${!OPTIND}"
            OPTIND=$((OPTIND + 1))
            ;;
          kind-podinfo) setup_kind_podinfo=1 ;;
          dkd) use_dkd=1 ;;
          gitea-webhook) GITEA_SET_WEBHOOK=1 ;;
          minikube-dns) use_dnsmasq=1 ;;
          minikube-domain)
            minikube_domain="${!OPTIND}"
            OPTIND=$((OPTIND + 1))
            ;;
          minikube-addons)
            minikube_addons="${!OPTIND}"
            OPTIND=$((OPTIND + 1))
            ;;
          flux-path)
            use_flux=1
            flux_path="${!OPTIND}"
            OPTIND=$((OPTIND + 1))
            ;;
          flux-boostrap) flux_bootstrap=1 ;;
          flux-auth)
            flux_auth="${!OPTIND}"
            echo "$flux_auth" | grep -qFx -e ssh -e token -e login || exit_error "Invalid auth type for flux, should be ssh or token"
            OPTIND=$((OPTIND + 1))
            ;;
          flux-image-automation) flux_image_automation=1 ;;
          flux-local-helm) flux_local_helm=1 ;;
          argocd-path)
            use_argocd=1
            argocd_path="${!OPTIND}"
            OPTIND=$((OPTIND + 1))
            ;;
          docker-services)
            docker_services="$(echo "${!OPTIND}" | tr ',' ' ')"
            OPTIND=$((OPTIND + 1))
            ;;
          traefik-log)
            TRAEFIK_LOG_LEVEL="$(echo "${!OPTIND}" | tr ',' ' ')"
            OPTIND=$((OPTIND + 1))
            ;;
          nginx-log)
            NGINX_LOG_LEVEL="$(echo "${!OPTIND}" | tr ',' ' ')"
            OPTIND=$((OPTIND + 1))
            ;;
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
  if [ $use_kind -eq 1 ] && [ $use_minikube -eq 1 ]; then
    exit_error "Unable to setup minikube and kind at the same time, please choose --kind or --minikube, not both."
  fi
  if [ $use_flux -eq 1 ] && [ -z "$flux_path" ]; then
    exit_error "Unable to setup flux without a path, please choose --flux-path <path>."
  fi
  [ "$flux_local_helm" -eq 1 ] && docker_services="$docker_services helm"
  # Ensure to use dnsmasq only with minikube
  [ $use_minikube -eq 0 ] && use_dnsmasq=0
  export use_ssl
  export use_minikube
  export start_minikube_dashboard
  export minikube_domain
  export minikube_addons
  export use_kind
  export KIND_HTTP_PORT
  export KIND_HTTPS_PORT
  export setup_kind_podinfo
  export use_dnsmasq
  export use_flux
  export flux_path
  export flux_bootstrap
  export flux_auth
  export flux_image_automation
  export flux_local_helm
  export use_argocd
  export argocd_path
  export docker_services
  export use_dkd
  export GITEA_SET_WEBHOOK
  export NGINX_LOG_LEVEL
  export TRAEFIK_LOG_LEVEL
  return 0
}
