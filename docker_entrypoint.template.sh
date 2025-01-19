#! /bin/bash

export PS4=$'+ \t\t''\e[33m\s@\v ${BASH_SOURCE:-}#\e[35m${LINENO} \e[34m${FUNCNAME[0]:+${FUNCNAME[0]}() }''\e[36m\t\e[0m\n'
[ "$DEBUG_FULL" -eq 1 ] && set -eoxu pipefail

{
  if [ "$(docker info -f json 2>/dev/null | jq .ID | grep -v null | xargs echo | wc -w)" -eq 0 ]; then
    echo '{ "data-root": "/docker-data" }' | jq . | sudo tee /etc/docker/daemon.json >/dev/null
    echo "Starting docker daemon in background"
    sudo su root -c 'nohup dockerd --config-file /etc/docker/daemon.json 2>&1' | sudo tee ~/dockerd.log >/dev/null &
  fi
} &

cpt=10
while [ "$(sudo docker info -f json 2>/dev/null | jq .ID | grep -v null | xargs echo | wc -w)" -eq 0 ] && [ $cpt -gt 0 ]; do
  echo "Waiting for docker to start"
  sleep 1
  cpt=$((cpt - 1))
done

[ "$(sudo docker info -f json 2>/dev/null | jq .ID | grep -v null | xargs echo | wc -w)" -eq 0 ] && {
  echo "Unable to start docker daemon"
  sudo cat ~/dockerd.log
  exit 1
}

docker_compose_name=services

cat <<-EOM >docker-compose/docker-compose.env
DOCKER_COMPOSE_NAME=$docker_compose_name
PORTAINER_PORT=${PORTAINER_PORT}
GITEA_PORT=${GITEA_PORT}
GITEA_SET_WEBHOOK=${GITEA_SET_WEBHOOK}
REGISTRY_PORT=${REGISTRY_PORT}
REGISTRY_UI_PORT=${REGISTRY_UI_PORT}
HELM_PORT=${HELM_PORT}
DNSMASQ_PORT=${DNSMASQ_PORT}
DNSMASQ_UI_PORT=${DNSMASQ_UI_PORT}
PODINFO_PORT=${PODINFO_PORT}
WHOAMI_PORT=${WHOAMI_PORT}
NGINX_PORT=${NGINX_PORT}
NGINX_INDEX=index-localarch.html
DKD_PORT=${DKD_PORT}
TRAEFIK_PORT=${TRAEFIK_PORT}
TRAEFIK_DASHBOARD_PORT=${TRAEFIK_DASHBOARD_PORT}
MINIKUBE_DASHBOARD_PORT=${MINIKUBE_DASHBOARD_PORT}
EOM

if ! git diff --quiet docker-compose/docker-compose.env; then
  git add docker-compose/docker-compose.env
  git commit -m "Update docker-compose/docker-compose.env"
fi

if [ -n "$DOCKER_CLEAN_SERVICES" ]; then
  for service in $(echo "$DOCKER_CLEAN_SERVICES" | tr ',' ' '); do
    case "$service" in
      minikube) : volume="$service" ;;
      registry | gitea | helm | portainer) volume="${docker_compose_name}_${service}" ;;
      *)
        echo "Unknown service $service"
        exit 1
        ;;
    esac
    case "$service" in
      registry) service='docker-registry' ;;
      helm) service='helm-registry' ;;
    esac
    sudo docker volume ls -q | grep -qFx "$volume" && {
      echo "Removing docker volume $service"
      if sudo docker container ls --format '{{.Names}}' | grep -qFx "$service"; then
        sudo docker container stop "$service" >/dev/null
      fi
      if sudo docker container ls --format '{{.Names}}' -a | grep -qFx "$service"; then
        sudo docker container rm "$service" >/dev/null
      fi
      sudo docker volume rm "$volume" >/dev/null
    }
  done
fi

scenario_traefik_minikube() {
  printf "\nLets play with flux and traefik on minikube...\n"
  sleep 5
  message="Hello from minikube cluster inside the localarch docker container"
  PODINFO_UI_MESSAGE="$message" ./start.sh --minikube $minikube_dashboard_param --flux-path k8s/flux-playground/traefik-minikube --minikube-addons "ingress ingress-dns" --minikube-dns --docker-services gitea,dnsmasq

  printf "\nChecking how whoami answers...\n"
  if kubectl wait --for=condition=available --timeout=60s deployment/whoami -n playground-traefik-minikube; then
    kubectl get pods -l app=whoami -n playground-traefik-minikube -o wide
    for i in $(seq 1 10); do
      [ "$(curl -s -o /dev/null -w "%{http_code}" http://whoami.traefik.minikube)" -eq 200 ] && break
      sleep "$i"
    done
  fi
  curl -sSfI http://whoami.traefik.minikube
  curl -sSf http://whoami.traefik.minikube

  printf "\nChecking how podinfo answers...\n"
  if kubectl wait --for=condition=available --timeout=150s deployment/podinfo -n info; then
    kubectl get pods -l app=podinfo -n info -o wide
    for i in $(seq 1 10); do
      [ "$(curl -s -o /dev/null -w "%{http_code}" http://podinfo.minikube)" -eq 200 ] && break
      sleep "$i"
    done
  fi
  curl -sSf http://podinfo.minikube
  printf "\n\n"

  if [ "$(curl -sSf http://podinfo.minikube | jq -r '.message')" = "$message" ]; then
    echo "Flux on minikube is ready"
  else
    echo "An error occured with flux or minikube, please check the logs. You might just need to wait a bit."
  fi
}

scenario_traefik_minikube_vault_helm() {
  printf "\nLets play with flux to orchestrate external-secrets vault, local helm and traefik on minikube...\n"
  sleep 5
  message="Hello from minikube cluster inside the localarch docker container"
  PODINFO_UI_MESSAGE='Hello from minikube local cluster' ./start.sh --minikube $minikube_dashboard_param --gitea-webhook --flux-image-automation --flux-path k8s/flux-playground/traefik-minikube-vault-helm --minikube-addons "ingress ingress-dns" --minikube-dns --docker-services gitea,registry,registry-ui,helm,dnsmasq,dkd,nginx,traefik

  printf "\nChecking how whoami answers...\n"
  if kubectl wait --for=condition=available --timeout=60s deployment/apps-mychart-whoami -n apps; then
    kubectl get pods -l app.kubernetes.io/name=mychart -l app.kubernetes.io/instance=apps -l app.kubernetes.io/component=whoami -n apps -o wide
    for i in $(seq 1 10); do
      [ "$(curl -s -o /dev/null -w "%{http_code}" http://whoami.traefik.minikube)" -eq 200 ] && break
      sleep "$i"
    done
  fi
  curl -sSfI http://whoami.traefik.minikube
  curl -sSf http://whoami.traefik.minikube

  printf "\nChecking how podinfo answers...\n"
  if kubectl wait --for=condition=available --timeout=150s deployment/apps-mychart-podinfo -n apps; then
    kubectl get pods -l app.kubernetes.io/name=mychart -l app.kubernetes.io/instance=apps -l app.kubernetes.io/component=podinfo -n apps -o wide
    for i in $(seq 1 10); do
      [ "$(curl -s -o /dev/null -w "%{http_code}" http://podinfo.traefik.minikube)" -eq 200 ] && break
      sleep "$i"
    done
  fi
  curl -sSf http://podinfo.traefik.minikube
  printf "\n\n"

  printf "\nChecking how flux automated server answers...\n"
  curl http://flux-automated.traefik.minikube/
  printf "\n\n"

  printf "\nBuilding new flux automated image...\n"
  ./docker/docker-build.sh flux-automated 2025-01-01-00-00.7
  printf "\n\n"

  printf "\nWait for flux to reconcialiate...\n"
  while read -r line; do
    # shellcheck disable=SC2086
    set $line
    echo "Waiting for $1/$2 to reconcile..."
    flux reconcile kustomization -n "$1" "$2" --timeout 5m --with-source
    echo
  done < <(kubectl get -A kustomizations.kustomize.toolkit.fluxcd.io --no-headers -o custom-columns=NAME:.metadata.namespace,RSRC:.metadata.name)

  printf "\nChecking how flux automated server answers now...\n"
  curl http://flux-automated.traefik.minikube/
  printf "\n\n"

  error=0
  if [ "$(curl -sSf http://podinfo.traefik.minikube | jq -r '.message')" = "Hello from cluster. Check swagger at /swagger/index.html. I also have a secret, the api admin password is change-that-password" ]; then
    echo "Podinfo replied as expected"
  else
    error=1
  fi
  if curl -sSf http://flux-automated.traefik.minikube/ | grep -q 'flux-automated version 2025-01-01-00-00.7 is running'; then
    echo "Flux automated replied as expected"
  else
    error=1
  fi
  printf "\n\n"

  if [ "$error" -eq 1 ]; then
    echo "An error occured with flux or minikube, please check the logs. You might just need to wait a bit."
  else
    echo "Flux on minikube is ready"
  fi
}

# Ensure to clean minikube cluster data from previous run, stored in the volume
minikube delete
(cd ~/.minikube && for file in *; do [ ! "$file" = "cache" ] && rm -rf ./"$file"; done)

debug_param=
[ "$DEBUG_FULL" -eq 1 ] && debug_param="--debug-full"
set +x

minikube_dashboard_param=
[ "$START_MINIKUBE_DASHBOARD" -eq 1 ] && minikube_dashboard_param="--minikube-dashboard"

[ -z "$DOCKER_SERVICES" ] && DOCKER_SERVICES=portainer,gitea,helm

if [ "$START_MINIKUBE" -eq 1 ]; then
  if ./start.sh --minikube $minikube_dashboard_param --docker-services "$DOCKER_SERVICES" $debug_param; then
    echo "minikube cluster is ready"

    # Expose the kubernetes api server
    kubectl --context minikube proxy --port 8443 --address=0.0.0.0 &

    # Run the scenario if provided
    if [ -n "$LOCAL_INFRA_SCENARIO" ]; then
      case "$LOCAL_INFRA_SCENARIO" in
        traefik-minikube) scenario_traefik_minikube ;;
        traefik-minikube-vault-helm) scenario_traefik_minikube_vault_helm ;;
        *)
          echo "Unknown scenario $LOCAL_INFRA_SCENARIO"
          exit 1
          ;;
      esac
    fi
  else
    echo "An error occured with minikube, please check the logs"
  fi
fi

if [ "$START_KIND" -eq 1 ]; then
  if ./start.sh --kind --docker-services "$DOCKER_SERVICES" $debug_param; then
    echo "kind cluster is ready"
  else
    echo "An error occured with minikube, please check the logs"
  fi
fi

cat <<EOM


Here are some usefull commands to interact with the localarch container:

- check the logs: docker logs -f localarch
- connect to localarch container: docker exec -it localarch bash
  - run minikube cluster: ./start.sh --minikube --flux-path k8s/flux-playground/traefik-minikube --minikube-addons "ingress ingress-dns" --minikube-dns --docker-services gitea,helm,dnsmasq --debug-full
  - run minikube cluster with more complex scenario: PODINFO_UI_MESSAGE='Hello from minikube local cluster' ./start.sh --minikube --gitea-webhook --flux-image-automation --flux-path k8s/flux-playground/traefik-minikube-vault-helm --minikube-addons "ingress ingress-dns" --minikube-dns --docker-services gitea,registry,registry-ui,helm,dnsmasq,dkd,traefik,nginx --debug-full
  - run kind cluster (does not work yet): ./start.sh --kind --debug-full
  - check all resource on cluster: kubectl get all -A
  - check all kind of resources on cluster: kubectl api-resources --sort-by name
  - check minikube cluster: k9s -A --context minikube -c deployment
  - check kind cluster: k9s -A --context kind-kind -c deployment
  - check whoami: curl -sSf http://whoami.traefik.minikube
  - check podinfo: curl -sSf http://podinfo.minikube

EOM

tail -f /dev/null
