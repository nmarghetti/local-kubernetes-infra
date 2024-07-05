FROM ubuntu:24.04

ARG USER=apprunner
ARG UID=1000

ENV USER=$USER

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
RUN useradd -ms /bin/bash -u $UID $USER \
  && echo "$USER ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/"$USER" && chmod 0440 /etc/sudoers.d/"$USER"

# Install some tools
RUN DEBIAN_FRONTEND=noninteractive \
  sudo apt-get update \
  && sudo apt-get install -y git curl vim \
  && sudo rm -rf /var/lib/apt/lists/*

# Install k9s
RUN curl -fsSL -o k9s_linux_amd64.deb https://github.com/derailed/k9s/releases/download/v0.32.4/k9s_linux_amd64.deb \
  && sudo apt install -y ./k9s_linux_amd64.deb \
  && rm ./k9s_linux_amd64.deb


# Copy all needed files
COPY . /app
RUN chown -R $USER:$USER /app


USER $USER

# Init the git repository
RUN ssh-keygen -t rsa -b 4096 -f "$HOME/.ssh/id_rsa" -N "" \
  && cd /app \
  && git config --global init.defaultBranch main \
  && git config --global user.email "apprunner@git.com" \
  && git config --global user.name $USER \
  && git init \
  && git add . \
  && git commit -m "Initial commit"

# Add certificates to minikube
RUN mkdir -p /home/$USER/.minikube/certs \
  && cp /app/certificates/*.crt /home/$USER/.minikube/certs/

# Install dependencies
RUN /app/scripts/setup_deps.sh

WORKDIR /app

ENTRYPOINT [ "bash" ]

CMD [ "/app/docker_entrypoint.sh" ]
