#! /bin/bash

get_dockerfile_deps() {
  grep -E "^ARG $1=" ./Dockerfile | cut -d= -f2 || exit_error "Unable to find '$1' in ./Dockerfile"
}

install_deps() {
  local dependencies="curl jq git gitk grc"
  local dependencies_to_install=
  local dep

  log_info "Checking dependencies: $dependencies"
  for dep in $dependencies; do
    ! type "$dep" >/dev/null 2>&1 && dependencies_to_install="$dependencies_to_install $dep"
  done

  ! type lsb_release >/dev/null 2>&1 && dependencies_to_install="$dependencies_to_install software-properties-common"
  ! type gpg >/dev/null 2>&1 && dependencies_to_install="$dependencies_to_install gnupg"
  ! type envsubst >/dev/null 2>&1 && dependencies_to_install="$dependencies_to_install gettext"
  ! type netcat >/dev/null 2>&1 && dependencies_to_install="$dependencies_to_install netcat-openbsd"
  ! type netstat >/dev/null 2>&1 && dependencies_to_install="$dependencies_to_install net-tools"
  ! type ip >/dev/null 2>&1 && dependencies_to_install="$dependencies_to_install iproute2"
  ! type sponge >/dev/null 2>&1 && dependencies_to_install="$dependencies_to_install moreutils"
  ! type htpasswd >/dev/null 2>&1 && dependencies_to_install="$dependencies_to_install apache2-utils"
  ! type nslookup >/dev/null 2>&1 && dependencies_to_install="$dependencies_to_install dnsutils"
  ! type ping >/dev/null 2>&1 && dependencies_to_install="$dependencies_to_install iputils-ping"

  [ -n "$dependencies_to_install" ] && {
    log_step "Installing dependencies: $dependencies_to_install"
    log_command "sudo apt-get update && sudo apt-get install -y $dependencies_to_install"
    # shellcheck disable=SC2086
    sudo apt-get update && sudo apt-get install -y $dependencies_to_install
  }

  for dep in $dependencies envsubst netcat netstat ip sponge htpasswd nslookup; do
    ! type "$dep" >/dev/null 2>&1 && echo "'$dep' is not available" && return 1
  done

  return 0
}

install_kubectl() {
  # shellcheck disable=SC2155
  local kubectl_version=$(get_dockerfile_deps KUBECTL_VERSION)
  log_info "Checking kubectl $kubectl_version"
  if ! type kubectl >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install -y apt-transport-https ca-certificates curl gnupg
    curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${kubectl_version}/deb/Release.key" | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    sudo chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    printf 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v%s/deb/ /\n' "${kubectl_version}" | sudo tee /etc/apt/sources.list.d/kubernetes.list
    sudo chmod 644 /etc/apt/sources.list.d/kubernetes.list
    sudo apt-get update
    sudo apt-get install -y kubectl
  fi
  type kubectl >/dev/null 2>&1 || return 1
}

install_helm() {
  log_info "Checking helm"
  if ! type helm >/dev/null 2>&1; then
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  fi
  type helm >/dev/null 2>&1 || return 1
}

install_yq() {
  log_info "Checking yq"
  if ! type yq >/dev/null 2>&1; then
    run_command sudo curl -L -o /usr/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 &&
      sudo chmod a+x /usr/bin/yq
  fi
  type yq >/dev/null 2>&1 || return 1
}

install_minikube() {
  # shellcheck disable=SC2155
  local minkube_version=$(get_dockerfile_deps MINIKUBE_VERSION)
  log_info "Checking minikube $minkube_version"
  if ! type minikube >/dev/null 2>&1 ||
    ! (printf '%s\n%s\n' "$(minikube version -o json | jq -r '.minikubeVersion' | sed -re 's/^v?(.*)$/\1/')" "$minkube_version" | sort -r --check=quiet --version-sort); then
    run_command curl -fsSLO https://storage.googleapis.com/minikube/releases/v${MINIKUBE_VERSION}/minikube-linux-amd64 &&
      sudo install -m 555 minikube-linux-amd64 /usr/local/bin/minikube &&
      rm minikube-linux-amd64
  fi
  type minikube >/dev/null 2>&1 || return 1
}

install_kind() {
  # shellcheck disable=SC2155
  local kind_version=$(get_dockerfile_deps KIND_VERSION)
  log_info "Checking kind $kind_version"
  if ! type kind >/dev/null 2>&1 ||
    ! (printf '%s\n%s\n' "$(kind --version | awk '{ print $3 }')" "$kind_version" | sort -r --check=quiet --version-sort); then
    run_command curl -fsSLO https://kind.sigs.k8s.io/dl/v${KIND_VERSION}/kind-linux-amd64 &&
      sudo install -m 555 kind-linux-amd64 /usr/local/bin/kind &&
      rm kind-linux-amd64
  fi
  type kind >/dev/null 2>&1 || return 1
}

install_docker() {
  log_info "Checking docker"
  # Install docker
  if ! apt list --installed 2>/dev/null | grep -qE '^containerd.io/'; then
    # Remove old configuration of docker
    if [ -d ~/.docker ]; then
      mv -f ~/.docker ~/.docker.backup
    fi

    # Remove other dependencies that can conflict with docker
    for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
      sudo apt remove -y $pkg
    done

    # Add Docker's official GPG key:
    if [ ! -f "/etc/apt/keyrings/docker.gpg" ]; then
      sudo mkdir -p /etc/apt/keyrings
      sudo apt-get update && sudo apt-get install -y ca-certificates curl gnupg
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
      sudo chmod a+r /etc/apt/keyrings/docker.gpg
    fi

    # Add the repository to Apt sources:
    if ! grep ^ /etc/apt/sources.list /etc/apt/sources.list.d/* | grep 'https://download.docker.com/linux/ubuntu' | grep -q 'https://download.docker.com/linux/ubuntu'; then
      echo "deb [arch=\"$(dpkg --print-architecture)\" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \"$(. /etc/os-release && echo "$VERSION_CODENAME")\" stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
      sudo apt-get update
    fi

    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  fi
  groups | tr '[:space:]' '\n' | grep -qFx docker || sudo usermod -aG docker "$USER"

  type docker >/dev/null 2>&1 || return 1
}

install_flux() {
  # Check latest version of flux with: flux check --pre
  # shellcheck disable=SC2155
  local minimumFluxVersion=$(get_dockerfile_deps FLUX_VERSION)
  log_info "Checking flux version $minimumFluxVersion"
  if ! type flux >/dev/null 2>&1 || ! printf '%s\n%s\n' "$(flux version --client -o json | jq '.flux' | xargs printf "%s" | sed -re 's/^v(.*)$/\1/')" "$minimumFluxVersion" | sort -r --check=quiet --version-sort; then
    log_step "Installing flux $minimumFluxVersion"
    log_command "curl -sS https://fluxcd.io/install.sh | sudo FLUX_VERSION=$minimumFluxVersion bash"
    curl -sS https://fluxcd.io/install.sh | sudo FLUX_VERSION="$minimumFluxVersion" bash
  fi
  type flux >/dev/null 2>&1 || exit_error "Unable to install flux"
}

install_argocd() {
  log_info "Checking argocd"
  if ! type argocd >/dev/null 2>&1; then
    curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
    sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
    rm argocd-linux-amd64
  fi
  type argocd >/dev/null 2>&1 || exit_error "Unable to install argocd"
}

install_mkcert() {
  log_info "Checking mkcert"
  if ! type mkcert >/dev/null 2>&1; then
    run_command sudo curl -L -o /usr/bin/mkcert https://dl.filippo.io/mkcert/latest?for=linux/amd64 &&
      sudo chmod a+x /usr/bin/mkcert
  fi
  type mkcert >/dev/null 2>&1 || return 1
}

install_k9s() {
  # shellcheck disable=SC2155
  local k9s_version=$(get_dockerfile_deps K9S_VERSION)
  log_info "Checking k9s"
  if ! type k9s >/dev/null 2>&1; then
    run_command curl -fsSL -o k9s_linux_amd64.deb "https://github.com/derailed/k9s/releases/download/v${k9s_version}/k9s_linux_amd64.deb" &&
      sudo apt install -y ./k9s_linux_amd64.deb &&
      rm ./k9s_linux_amd64.deb
  fi
  type k9s >/dev/null 2>&1 || return 1
}

install_terraform() {
  log_info "Checking terraform"
  if ! type terraform >/dev/null 2>&1; then
    wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg >/dev/null &&
      gpg --no-default-keyring --keyring /usr/share/keyrings/hashicorp-archive-keyring.gpg --fingerprint &&
      echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list &&
      sudo apt update &&
      sudo apt-get install terraform &&
      terraform -install-autocomplete
  fi
  type terraform >/dev/null 2>&1 || return 1
}

setup_deps() {
  install_deps || exit_error "Unable to install dependencies"
  install_yq || exit_error "Unable to install yq"
  install_mkcert || exit_error "Unable to install mkcert"
  install_docker || exit_error "Unable to install docker"
  install_kubectl || exit_error "Unable to install kubectl"
  install_helm || exit_error "Unable to install helm"
  install_minikube || exit_error "Unable to install minikube"
  install_kind || exit_error "Unable to install kind"
  install_k9s || exit_error "Unable to install k9s"
  install_flux || exit_error "Unable to install flux"
  install_argocd || exit_error "Unable to install argocd"
  install_terraform || exit_error "Unable to install terraform"
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

  setup_deps

  exit 0
}
