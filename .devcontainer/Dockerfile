##################### From Dockerfile at root of the repository #####################
FROM ubuntu:24.04

ARG USERNAME=apprunner
ARG UID=1000

ENV USER=$USERNAME

# apt packages
ARG APT_PACKAGES="bash-completion curl jq git gitk grc software-properties-common gnupg gettext netcat-openbsd net-tools iproute2 moreutils apache2-utils dnsutils iputils-ping"
# yq
ARG YQ_INSTALL=1
# mkcert
ARG MKCERT_INSTALL=1
# docker
ARG DOCKER_INSTALL=1
ARG DOCKER_GID
# helm
ARG HELM_INSTALL=1
# kubectl
ARG KUBECTL_INSTALL=1
ARG KUBECTL_VERSION=1.31
# k9s
ARG K9S_INSTALL=1
ARG K9S_VERSION=0.32.5
# flux
ARG FLUX_INSTALL=1
ARG FLUX_VERSION=2.4.0
ENV FLUX_VERSION=$FLUX_VERSION
# argocd
ARG ARGOCD_INSTALL=1
ARG ARGOCD_VERSION=2.13.3
# kind
ARG KIND_INSTALL=1
ARG KIND_VERSION=0.23.0
# minikube
ARG MINIKUBE_INSTALL=1
ARG MINIKUBE_VERSION=1.35.0
# terraform
ARG TERRAFORM_INSTALL=1

# Install sudo and root certificates
RUN DEBIAN_FRONTEND=noninteractive \
  apt-get update \
  && apt-get install -y sudo ca-certificates \
  && rm -rf /var/lib/apt/lists/*
COPY ./certificates /certificates
RUN if [ "$(find /certificates -type f -name "*.crt" -exec basename '{}' \; | grep -cvE '^ca-bundle.crt$')" -ne 0 ]; then \
      find /certificates -type f ! -name ca-bundle.crt -name "*.crt" -exec cp '{}' /usr/local/share/ca-certificates/ \;; \
      update-ca-certificates; \
    fi \
  && rm -rf /certificates

# Delete ubuntu user
RUN userdel --remove ubuntu

# Add user as sudoer
RUN useradd -ms /bin/bash -u $UID $USERNAME \
  && echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/"$USERNAME" && chmod 0440 /etc/sudoers.d/"$USERNAME"

# Install some tools
RUN if test -n "$APT_PACKAGES" ; then \
    DEBIAN_FRONTEND=noninteractive \
    sudo apt-get update \
      && sudo apt-get install -y $APT_PACKAGES \
      && sudo rm -rf /var/lib/apt/lists/* \
  ; fi

# Install yq
RUN if test $YQ_INSTALL -eq 1; then \
    sudo curl -L -o /usr/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 \
      && sudo chmod +x /usr/bin/yq \
  ; fi

# Install mkcert
RUN if test $MKCERT_INSTALL -eq 1; then \
    sudo curl -L -o /usr/bin/mkcert https://dl.filippo.io/mkcert/latest?for=linux/amd64 \
      && sudo chmod +x /usr/bin/mkcert \
  ; fi

# Install docker and add user to docker group
RUN if test $DOCKER_INSTALL -eq 1; then \
    sudo mkdir -p /etc/apt/keyrings \
      && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
      && sudo chmod a+r /etc/apt/keyrings/docker.gpg \
      && echo "deb [arch=\"$(dpkg --print-architecture)\" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \"$(. /etc/os-release && echo "$VERSION_CODENAME")\" stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null \
      && if test -n "$DOCKER_GID"; then sudo groupadd -g "$DOCKER_GID" docker; fi \
      && DEBIAN_FRONTEND=noninteractive sudo apt-get update \
      && sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
      && sudo rm -rf /var/lib/apt/lists/*\
      && sudo usermod -aG docker $USERNAME \
  ; fi

# Install kubectl
RUN if test $KUBECTL_INSTALL -eq 1; then \
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v${KUBECTL_VERSION}/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg \
      && printf 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v%s/deb/ /\n' "${KUBECTL_VERSION}" | sudo tee /etc/apt/sources.list.d/kubernetes.list \
      && DEBIAN_FRONTEND=noninteractive sudo apt-get update \
      && sudo apt-get install -y kubectl \
      && sudo rm -rf /var/lib/apt/lists/* \
  ; fi

# Install helm
RUN if test $HELM_INSTALL -eq 1; then \
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | sudo bash \
  ; fi

# Install minikube
RUN if test $MINIKUBE_INSTALL -eq 1; then \
    curl -fsSLO https://storage.googleapis.com/minikube/releases/v${MINIKUBE_VERSION}/minikube-linux-amd64 \
    && sudo install -m 555 minikube-linux-amd64 /usr/local/bin/minikube \
    && rm minikube-linux-amd64 \
  ; fi

# Install kind
RUN if test $KIND_INSTALL -eq 1; then \
    curl -fsSLO https://kind.sigs.k8s.io/dl/v${KIND_VERSION}/kind-linux-amd64 \
    && sudo install -m 555 kind-linux-amd64 /usr/local/bin/kind \
    && rm kind-linux-amd64 \
; fi

# Install k9s
RUN if test $K9S_INSTALL -eq 1; then \
    curl -fsSL -o k9s_linux_amd64.deb https://github.com/derailed/k9s/releases/download/v${K9S_VERSION}/k9s_linux_amd64.deb \
      && sudo apt install -y ./k9s_linux_amd64.deb \
      && rm ./k9s_linux_amd64.deb \
  ; fi

# Install flux
RUN if test $FLUX_INSTALL -eq 1; then \
    curl -sS https://fluxcd.io/install.sh | sudo bash \
  ; fi

# Install argocd
RUN if test $ARGOCD_INSTALL -eq 1; then \
    curl -sSLO https://github.com/argoproj/argo-cd/releases/download/v${ARGOCD_VERSION}/argocd-linux-amd64 \
      && sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd \
      && rm argocd-linux-amd64 \
  ; fi

# Install terraform
RUN if test $TERRAFORM_INSTALL -eq 1; then \
    curl -o - https://apt.releases.hashicorp.com/gpg | gpg --dearmor | tee /usr/share/keyrings/hashicorp-archive-keyring.gpg >/dev/null \
    && gpg --no-default-keyring --keyring /usr/share/keyrings/hashicorp-archive-keyring.gpg --fingerprint \
    && echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list \
    && apt update \
    && apt-get install terraform \
    && terraform -install-autocomplete \
; fi

##################### Specific to dev container #####################

RUN DEBIAN_FRONTEND=noninteractive \
  apt update \
  && curl -sSLO https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
  && sudo apt install -y ./google-chrome-stable_current_amd64.deb \
  && rm -f ./google-chrome-stable_current_amd64.deb \
  && apt clean


ENV HOSTNAME=DevContainer
USER $USERNAME

# Setup user config
COPY .devcontainer/shellrc.sh /home/$USERNAME/.shellrc.sh
RUN curl -L https://raw.github.com/git/git/master/contrib/completion/git-prompt.sh > ~/.bash_git_prompt \
    && echo "source ~/.bash_git_prompt" >> ~/.bashrc \
    && echo "source ~/.shellrc.sh" >> ~/.bashrc
RUN SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  && sudo mkdir /commandhistory \
  && sudo touch /commandhistory/.bash_history \
  && sudo chown -R $USERNAME /commandhistory \
  && echo "$SNIPPET" >> ~/.bashrc

ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt
