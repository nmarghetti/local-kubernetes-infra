#! /bin/bash

DEBUG=${DEBUG:-1}
EXIT_ON_ERROR=${EXIT_ON_ERROR:-0}

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GREY='\033[1;36m'
NC='\033[0m' # No Color

get_log() {
  local data
  if [ -n "$*" ]; then
    # Read data from arguments
    data="$*"
  elif [ ! -t 0 ]; then
    # Read data from stdin (pipe or <<EOM)
    IFS= read -r data <&0
  else
    data="I dont know what is there to log..."
  fi
  printf "%s\n" "$data"
}

log_info() {
  printf "${GREEN}%s${NC}\n" "$(get_log "$*")" >&2
}

log_debug() {
  printf "${GREY}%s${NC}\n" "$(get_log "$*")" >&2
}

log_step() {
  printf "${YELLOW}%s${NC}\n" "$(get_log "$*")" >&2
}

log_command() {
  printf "${CYAN}%s${NC}\n" "$(get_log "$*")" >&2
}

log_error() {
  printf "${RED}%s${NC}\n" "$(get_log "$*")" >&2
}

run_command() {
  [ "$DEBUG" = '1' ] && log_command "$@"
  "$@" || {
    status=$?
    log_error "[ERROR] The following command failed with status $status:" && log_command "$*"
    [ "$EXIT_ON_ERROR" = '1' ] && exit $status
  }
}

run_command_hide() {
  local command_output
  command_output=$(mktemp)
  trap "rm -f $command_output" INT TERM HUP EXIT

  [ "$DEBUG" = '1' ] && log_command "$@"
  "$@" &>"$command_output" || {
    status=$?
    log_error "[ERROR] The following command failed with status $status:" && log_command "$*"
    cat "$command_output" >&2
    [ "$EXIT_ON_ERROR" = '1' ] && exit $status
  }
}

run_command_piped() {
  local command_output
  command_output=$(mktemp)
  trap "rm -f $command_output" INT TERM HUP EXIT

  [ "$DEBUG" = '1' ] && log_command "$@"
  eval "$*" &>"$command_output" || {
    status=$?
    log_error "[ERROR] The following command failed with status $status:" && log_command "$*"
    cat "$command_output" >&2
    [ "$EXIT_ON_ERROR" = '1' ] && exit $status
  }
}

exit_error() {
  log_error "$@" >&2
  exit 1
}

export CERT_PATH=./docker-compose/docker/certificates

if type git >/dev/null 2>&1; then
  GIT_ROOT="$(git rev-parse --show-toplevel)"
  [ -n "$GIT_ROOT" ] || exit_error "Unable to retrieve the root of the git repository"
  # shellcheck source=../docker-compose/docker-compose.env
  [ -f "$GIT_ROOT"/docker-compose/docker-compose.env ] && . "$GIT_ROOT"/docker-compose/docker-compose.env
fi

usage() {
  cat <<EOM
Usage: $0 [options]

Options:
  -k, --no-ssl                            : do not use TLS (default)
  -s, --use-ssl                           : use TLS
  -d, --debug                             : debug mode (default)
      --debug-full                        : debug bash
    --minikube                            : setup minikube
    --minikube-dashboard                  : start minikube dashboard
    --kind                                : setup kind
    --docker-services <service[,service]> : select docker services, comma separated, to setup amongs $(yq .services -o json <./docker-compose/docker-compose.yaml | jq -r '[keys[] | select(. | startswith("init-") | not)] | join(",")') (default all)
    --dkd                                 : setup dkd image
    --gitea-webhook                       : setup gitea webhook to notify flux
    --flux-path <path>                    : select flux path amongs $(find ./k8s/flux-playground -maxdepth 2 -name "flux-system" | tr '\n' ',' | head -c -1)
    --flux-auth <auth>                    : select auth type for flux amongs ssh, token, login (default: ssh)
    --flux-image-automation               : add flux component for image automation
    --flux-local-helm                     : use local helm registry (default: false)
    --argocd-path <path>                  : select argocd path amongs $(find ./k8s/argocd-playground -maxdepth 2 -name "argocd" | tr '\n' ',' | head -c -1)
  -q                                      : quiet mode, print less information
  -h                                      : display this help

Minikube options:
  --minikube-addons <addon [addon...]> : enable minikube addons eg. ingress,ingress-dns
  --minikube-dns                       : setup dnsmasq to resolve cluster domain (0|1, default: 0)
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
  use_dkd=0
  use_flux=0
  flux_path=""
  flux_auth="ssh"
  flux_image_automation=0
  flux_local_helm=0
  GITEA_SET_WEBHOOK=0
  use_argocd=0
  argocd_path=""
  use_dnsmasq=0
  minikube_addons=
  docker_services=portainer
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
          dkd) use_dkd=1 ;;
          gitea-webhook) GITEA_SET_WEBHOOK=1 ;;
          minikube-dns)
            use_dnsmasq="${!OPTIND}"
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
  export minikube_addons
  export use_kind
  export use_dnsmasq
  export use_flux
  export flux_path
  export flux_auth
  export flux_image_automation
  export flux_local_helm
  export use_argocd
  export argocd_path
  export docker_services
  export use_dkd
  export GITEA_SET_WEBHOOK
  return 0
}
