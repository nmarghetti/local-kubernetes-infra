#! /bin/bash

setup_flux() {
  if [ "$use_minikube" -eq 0 ] && [ "$use_kind" -eq 0 ]; then
    exit_error "You did not choose if you use minikube or kind (--kind | --minikube)"
  fi

  # Generate helm repositories
  flux_helm_repositories=k8s/flux/base/helm-repositories
  flux_helm_cluster_url=$(echo "$helm_url" | sed -re "s#localhost#${DOCKER_COMPOSE_HOST}#")
  for helm_repo in "${flux_helm_repositories}"/*; do
    [ ! -d "$helm_repo" ] && continue
    flux_helm_repository="$helm_repo/repo.yaml"
    [ ! -f "$flux_helm_repository" ] && log_error "Unable to find '$helm_repo/repo.yaml' file"
    helm_repo_name=$(basename "$helm_repo")
    if [ "$flux_local_helm" -eq 1 ] || [ "$helm_repo_name" = "mychart" ]; then
      grep -q "$flux_helm_cluster_url" "$flux_helm_repository" && continue
      log_info "Creating flux repositories yaml manifest ($flux_helm_repository)"
      if [ "$use_ssl" -eq 0 ]; then
        run_command flux create source helm \
          --url "$flux_helm_cluster_url" \
          --export "$helm_repo_name" >"$flux_helm_repository"
      else
        run_command flux create secret tls \
          --tls-key-file=./docker-compose/docker/certificates/helm-client_tls.key \
          --tls-crt-file=./docker-compose/docker/certificates/helm-client_tls.crt \
          --ca-crt-file=./docker-compose/docker/certificates/ca.crt \
          --export "${helm_repo_name}-helm-secret" >"$flux_helm_repository"
        run_command flux create source helm \
          --url "$flux_helm_cluster_url" \
          --secret-ref "${helm_repo_name}-helm-secret" \
          --export "$helm_repo_name" >>"$flux_helm_repository"
      fi
    else
      declare -A flux_online_helm_repositories=(
        ['external-secrets-io']='https://charts.external-secrets.io'
        ['kubernetes-replicator']='https://helm.mittwald.de'
        ['reloader']='https://stakater.github.io/stakater-charts'
        ['traefik']='https://traefik.github.io/charts'
      )
      [[ ! -v flux_online_helm_repositories[$helm_repo_name] ]] && continue
      flux_helm_repository_url=${flux_online_helm_repositories[$helm_repo_name]}
      grep -q "$flux_helm_repository_url" "$flux_helm_repository" && continue
      log_info "Creating flux repositories yaml manifest ($flux_helm_repository)"
      run_command flux create source helm \
        --url "$flux_helm_repository_url" \
        --export "$helm_repo_name" >"$flux_helm_repository"
    fi
  done
  if ! git diff --exit-code "$flux_helm_repositories" >/dev/null; then
    git add "$flux_helm_repositories" &&
      git commit -m "Update $flux_helm_repositories" &&
      run_command git push --quiet gitea main
  fi

  # Generate image repositories
  flux_image_repositories=k8s/flux/base/image-repositories
  mkdir -p "$flux_image_repositories"
  for image_repo in "${flux_image_repositories}"/*; do
    [ ! -d "$image_repo" ] && continue
    image_name=$(basename "$image_repo")
    flux_image_repository="$image_repo/repo.yaml"
    if [ "$use_ssl" -eq 0 ]; then
      run_command flux create image repository "$image_name" --image="${DOCKER_COMPOSE_HOST}:${REGISTRY_PORT}/${image_name}" --interval=5m --export | yq eval '.spec.insecure = true' >"$flux_image_repository"
    fi
  done
  if ! git diff --exit-code "$flux_image_repositories" >/dev/null; then
    git add "$flux_image_repositories" &&
      git commit -m "Update $flux_image_repositories" &&
      run_command git push --quiet gitea main
  fi

  if [ -z "$flux_path" ] || [ ! -e "$flux_path" ]; then
    log_info "flux_path is not set or does not exist, ignoring flux setup"
    return 0
  fi

  if [ -d "$flux_path/flux-system/flux-system" ]; then
    flux_path="$flux_path/flux-system"
    log_info "Changing flux path to $flux_path"
  fi

  # Compute gitea repo url
  if [ "$flux_auth" = 'ssh' ]; then
    gitea_repo_url="ssh://git@${DOCKER_COMPOSE_HOST}:222/${gitea_admin}/${gitea_repo}.git"
  else
    gitea_repo_url='https'
    if [ "$use_ssl" -eq 0 ]; then
      gitea_repo_url="http"
    fi
    gitea_repo_url="${gitea_repo_url}://${DOCKER_COMPOSE_HOST}:${GITEA_PORT}/${gitea_admin}/${gitea_repo}.git"
  fi

  flux_gotk_sync="$flux_path"/flux-system/gotk-sync.yaml
  if [ -f "$flux_gotk_sync" ]; then
    run_command sed -i -re "s#^  url: .*\$#  url: $gitea_repo_url#" "$flux_gotk_sync"
    if ! git diff --exit-code "$flux_gotk_sync" >/dev/null; then
      git add "$flux_gotk_sync" &&
        git commit -m "Update $flux_gotk_sync" &&
        run_command git push --quiet gitea main
    fi
  fi

  # Boostrap flux
  # Create certificate authority secret
  ./certificates/compute_ca_certificate.sh
  # Create certificates configmap
  ./scripts/flux_apply_certificates.sh

  # Minimum setup for external-secrets
  # helm install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace --set installCRDs=true
  # helm delete external-secrets --namespace external-secrets
  # ./k8s/secret/create_gcp_access_secret.sh || exit_error "Unable to setup GCP secret manager access"
  # external_secret_version=$(yq .spec.chart.spec.version <./k8s/flux_minikube/external-secret/releases.yaml)
  # [ ! "$external_secret_version" = "null" ] || exit_error "Unable to get external-secret chart version"
  # kubectl get crd | grep -q external-secrets.io || kubectl apply -k "https://github.com/external-secrets/external-secrets/config/crds/bases?ref=v${external_secret_version}"
  # kubectl get crd | grep -q external-secrets.io || exit_error "Unable to install external-secrets.io crd"

  if ! kubectl get -n flux-system deployments.apps source-controller &>/dev/null; then
    bootstrap_intput=''
    bootstrap_params=(
      '--silent'
      '--branch=main'
      "--path=$flux_path"
      '--ca-file=./certificates/ca-bundle.crt'
    )
    [ "$flux_image_automation" -eq 1 ] && bootstrap_params+=('--components-extra=image-reflector-controller,image-automation-controller')
    if [ "$flux_auth" = 'ssh' ]; then
      grep -q "$DOCKER_COMPOSE_HOST" ~/.ssh/known_hosts || ssh-keyscan -p 222 "$DOCKER_COMPOSE_HOST" 2>/dev/null >>~/.ssh/known_hosts
      bootstrap_params+=(
        "--private-key-file=$HOME/.ssh/id_rsa"
      )
    else
      bootstrap_params+=('--token-auth')
      if [ "$flux_auth" = 'token' ]; then
        bootstrap_intput="$gitea_token"
      elif [ "$flux_auth" = 'login' ]; then
        bootstrap_params+=(
          "--username=$gitea_admin"
          "--password=$gitea_admin_pass"
        )
      fi
      if [ "$use_ssl" -eq 0 ]; then
        bootstrap_params+=('--allow-insecure-http')
      fi
    fi
    run_command flux bootstrap git "${bootstrap_params[@]}" --url="$gitea_repo_url" < <(echo "$bootstrap_intput")
    run_command git fetch --prune gitea
    if [ "$(git diff --stat main..gitea/main | wc -l)" -ne 0 ]; then
      run_command git pull --rebase gitea main
    fi
    # Use existing manifest in flux/base/flux-system
    "$GIT_ROOT"/scripts/flux_migrate.sh --flux-path "$flux_path" || exit_error "Unable to migrate flux"
  fi

  [ "$(kubectl get -n flux-system deployments.apps source-controller -o json | jq '.status.conditions[0].status' | xargs printf "%s")" = "True" ] || exit_error "Unable to start flux"

  if [ "$(basename "$flux_path")" = 'flux-system' ]; then
    flux_path="$(dirname "$flux_path")"
  fi
  [ -f "$flux_path/post_install.sh" ] && run_command "$flux_path/post_install.sh"

  return 0
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
  # shellcheck source=./setup_docker_compose_services.sh
  . "$SCRIPTS"/setup_docker_compose_services.sh
  # shellcheck source=./setup_gitea.sh
  . "$SCRIPTS"/setup_gitea.sh
  # shellcheck source=./setup_minikube.sh
  . "$SCRIPTS"/setup_minikube.sh
  # shellcheck source=./setup_kind.sh
  . "$SCRIPTS"/setup_kind.sh
  # shellcheck source=./setup_cluster_access.sh
  . "$SCRIPTS"/setup_cluster_access.sh

  cd "$GIT_ROOT" || exit_error "Unable to go to git root folder"

  parse_args "$@"

  compute_docker_compose_services_access
  compute_gitea_access
  compute_cluster_access
  setup_flux

  exit 0
}
