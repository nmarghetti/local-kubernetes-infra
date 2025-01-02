#! /bin/bash

install_deps() {
  local dependencies="curl jq"
  local dependencies_to_install=
  local dep
  log_info "Checking dependencies: $dependencies ip sponge htpasswd"
  for dep in $dependencies; do
    ! type "$dep" >/dev/null 2>&1 && dependencies_to_install="$dependencies_to_install $dep"
  done
  ! type "envsubst" >/dev/null 2>&1 && dependencies_to_install="$dependencies_to_install gettext"
  ! type "netcat" >/dev/null 2>&1 && dependencies_to_install="$dependencies_to_install netcat-openbsd"
  ! type "ip" >/dev/null 2>&1 && dependencies_to_install="$dependencies_to_install iproute2"
  ! type "sponge" >/dev/null 2>&1 && dependencies_to_install="$dependencies_to_install moreutils"
  ! type "htpasswd" >/dev/null 2>&1 && dependencies_to_install="$dependencies_to_install apache2-utils"
  ! type "nslookup" >/dev/null 2>&1 && dependencies_to_install="$dependencies_to_install dnsutils"
  [ -n "$dependencies_to_install" ] && {
    log_step "Installing dependencies: $dependencies_to_install"
    log_command "sudo apt-get update && sudo apt-get install -y $dependencies_to_install"
    # shellcheck disable=SC2086
    sudo apt-get update && sudo apt-get install -y $dependencies_to_install
  }
  for dep in $dependencies envsubst netcat ip sponge htpasswd nslookup; do
    ! type "$dep" >/dev/null 2>&1 && echo "'$dep' is not available" && return 1
  done

  return 0
}

install_kubectl() {
  local kubectl_version="1.31"
  log_info "Checking kubectl $kubectl_version"
  if ! type kubectl >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install -y apt-transport-https ca-certificates curl gnupg
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v${kubectl_version}/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    sudo chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${kubectl_version}/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
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
  local minkube_version="1.34.0"
  log_info "Checking minikube $minkube_version"
  if ! type minikube >/dev/null 2>&1 ||
    ! (printf '%s\n%s\n' "$(minikube version -o json | jq -r '.minikubeVersion' | sed -re 's/^v?(.*)$/\1/')" "$minkube_version" | sort -r --check=quiet --version-sort); then
    run_command sudo curl -fsSLo /usr/bin/minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 &&
      sudo chmod a+x /usr/bin/minikube
  fi
  type minikube >/dev/null 2>&1 || return 1
}

install_kind() {
  local kind_version="0.23.0"
  log_info "Checking kind $kind_version"
  if ! type kind >/dev/null 2>&1 ||
    ! (printf '%s\n%s\n' "$(kind --version | awk '{ print $3 }')" "$kind_version" | sort -r --check=quiet --version-sort); then
    run_command sudo curl -fsSLo /usr/bin/kind https://kind.sigs.k8s.io/dl/v$kind_version/kind-linux-amd64 &&
      sudo chmod a+x /usr/bin/kind
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
      echo \
        "deb [arch=\"$(dpkg --print-architecture)\" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
        \"$(. /etc/os-release && echo "$VERSION_CODENAME")\" stable" |
        sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
      sudo apt-get update
    fi

    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  fi
  groups | tr '[:space:]' '\n' | grep -qFx docker || sudo usermod -aG docker "$USER"

  type docker >/dev/null 2>&1 || return 1
}

install_flux() {
  # Check latest version of flux with: flux check --pre
  local minimumFluxVersion="2.4.0"
  log_info "Checking flux version $minimumFluxVersion"
  if ! type flux >/dev/null 2>&1 || ! printf '%s\n%s\n' "$(flux version --client -o json | jq '.flux' | xargs printf "%s" | sed -re 's/^v(.*)$/\1/')" "$minimumFluxVersion" | sort -r --check=quiet --version-sort; then
    log_step "Installing flux $minimumFluxVersion"
    log_command "curl -sS https://fluxcd.io/install.sh | sudo FLUX_VERSION=$minimumFluxVersion bash"
    curl -sS https://fluxcd.io/install.sh | sudo FLUX_VERSION=$minimumFluxVersion bash
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

setup_deps() {
  install_deps || exit_error "Unable to install dependencies"
  install_kubectl || exit_error "Unable to install kubectl"
  install_helm || exit_error "Unable to install helm"
  install_yq || exit_error "Unable to install yq"
  install_docker || exit_error "Unable to install docker"
  install_mkcert || exit_error "Unable to install mkcert"
  install_minikube || exit_error "Unable to install minikube"
  install_kind || exit_error "Unable to install kind"
  install_flux || exit_error "Unable to install flux"
  install_argocd || exit_error "Unable to install argocd"
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
