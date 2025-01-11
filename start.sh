#! /bin/bash

export PS4=$'+ \t\t''\e[33m\s@\v ${BASH_SOURCE:-}#\e[35m${LINENO} \e[34m${FUNCNAME[0]:+${FUNCNAME[0]}() }''\e[36m\t\e[0m\n'

cd "$(dirname "$(readlink -f "$0")")" || {
  echo "Unable to go to parent folder of $0" >&2
  exit 1
}

SCRIPTS=$(git rev-parse --show-toplevel)/scripts
# shellcheck source=scripts/common.sh
. "$SCRIPTS"/common.sh
# shellcheck source=scripts/setup_deps.sh
. "$SCRIPTS"/setup_deps.sh
# shellcheck source=scripts/setup_docker_compose_services.sh
. "$SCRIPTS"/setup_docker_compose_services.sh
# shellcheck source=scripts/setup_dkd.sh
. "$SCRIPTS"/setup_dkd.sh
# shellcheck source=scripts/setup_minikube.sh
. "$SCRIPTS"/setup_minikube.sh
# shellcheck source=scripts/setup_kind.sh
. "$SCRIPTS"/setup_kind.sh
# shellcheck source=scripts/setup_flux.sh
. "$SCRIPTS"/setup_flux.sh
# shellcheck source=scripts/setup_argocd.sh
. "$SCRIPTS"/setup_argocd.sh
# shellcheck source=scripts/setup_dnsmasq.sh
. "$SCRIPTS"/setup_dnsmasq.sh

parse_args "$@"

tmp_file_output=$(mktemp)
trap 'rm -f -- $tmp_file_output' INT TERM HUP EXIT

run_command setup_deps || exit_error "Unable to setup dependencies"
run_command setup_docker_compose_services || exit_error "Unable to setup docker compose services"
[ "$use_kind" -eq 1 ] && {
  run_command setup_kind || exit_error "Unable to setup kind"
}
[ "$use_minikube" -eq 1 ] && {
  run_command setup_minikube || exit_error "Unable to setup minikube"
}
[ "$use_dkd" -eq 1 ] && {
  run_command setup_dkd || exit_error "Unable to setup dkd"
}
[ "$use_flux" -eq 1 ] && {
  run_command setup_flux || exit_error "Unable to setup flux"
}
[ "$use_argocd" -eq 1 ] && {
  run_command setup_argocd || exit_error "Unable to setup argocd"
}
[ "$use_dnsmasq" -eq 1 ] && {
  run_command setup_dnsmasq || exit_error "Unable to setup dnsmasq"
}

# tmp_cert=$(mktemp)
# trap 'rm -f -- '"$tmp_cert" INT TERM HUP EXIT
# kubectl get -n flux-system configmaps kube-root-ca.crt -o json | jq '.data."ca.crt"' | xargs echo -e >"$tmp_cert"
# if [ ! -f /usr/local/share/ca-certificates/local_minikube_flux_ca.crt ] || ! cmp --silent "$tmp_cert" /usr/local/share/ca-certificates/local_minikube_flux_ca.crt; then
#   sudo cp -f "$tmp_cert" /usr/local/share/ca-certificates/local_minikube_flux_ca.crt
#   sudo update-ca-certificates -f
# fi

exit 0
