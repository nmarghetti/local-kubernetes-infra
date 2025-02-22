#! /bin/bash

cd "$(dirname "$(readlink -f "$0")")" || {
  echo "Unable to go to parent folder of $0" >&2
  exit 1
}

# export PS4=$'+ \t\t''\e[33m\s@\v ${BASH_SOURCE:-}#\e[35m${LINENO} \e[34m${FUNCNAME[0]:+${FUNCNAME[0]}() }''\e[36m\t\e[0m\n'

# # shellcheck source=../../../scripts/common.sh
# . ./common.sh
# # shellcheck source=../../../scripts/setup_deps.sh
# . ./setup_deps.sh

# install_kubectl || exit_error "Unable to install kubectl"
# install_helm || exit_error "Unable to install helm"

# curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
# sudo install -o root -g root -m 0755 kustomize /usr/local/bin/kustomize

# pwd
# curl -LO https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize/v3.5.4/kustomize_v3.5.4_linux_amd64.tar.gz &&
#   tar -xzvf kustomize_v3.5.4_linux_amd64.tar.gz &&
#   mv kustomize /usr/local/bin/
