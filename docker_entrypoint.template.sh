#! /bin/sh

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

cat <<-EOM >/app/docker-compose/docker-compose.env
DOCKER_COMPOSE_NAME=$docker_compose_name
PORTAINER_PORT=${PORTAINER_PORT}
GITEA_PORT=${GITEA_PORT}
REGISTRY_PORT=${REGISTRY_PORT}
REGISTRY_UI_PORT=${REGISTRY_UI_PORT}
HELM_PORT=${HELM_PORT}
DNSMASQ_PORT=${DNSMASQ_PORT}
DNSMASQ_UI_PORT=${DNSMASQ_UI_PORT}
PODINFO_PORT=${PODINFO_PORT}
WHOAMI_PORT=${WHOAMI_PORT}
NGINX_PORT=${NGINX_PORT}
EOM

if ! git diff --quiet docker-compose/docker-compose.env; then
  git add docker-compose/docker-compose.env
  git commit -m "Update docker-compose/docker-compose.env"
fi

if [ -n "$DOCKER_CLEAN_SERVICES" ]; then
  for service in $(echo "$DOCKER_CLEAN_SERVICES" | tr ',' ' '); do
    case "$service" in
      minikube) : ;;
      registry | gitea | helm | portainer) service="${docker_compose_name}_${service}" ;;
      *)
        echo "Unknown service $service"
        exit 1
        ;;
    esac
    sudo docker volume ls -q | grep -qw "$service" && {
      echo "Removing docker volume $service"
      sudo docker container stop "$service" >/dev/null
      sudo docker container rm "$service" >/dev/null
      sudo docker volume rm "$service" >/dev/null
    }
  done
fi

scenario_traefik_minikube() {
  printf "\nLets play with flux and traefik on minikube...\n"
  sleep 5
  message="Hello from minikube cluster inside the localarch docker container"
  PODINFO_UI_MESSAGE="$message" ./start.sh --minikube --flux-path k8s/flux-playground/traefik-minikube --minikube-addons "ingress ingress-dns" --minikube-dns 1 --docker-services gitea,dnsmasq

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
  PODINFO_UI_MESSAGE="$message" ./start.sh --minikube --flux-path k8s/flux-playground/traefik-minikube-vault-helm --minikube-addons "ingress ingress-dns" --minikube-dns 1 --docker-services gitea,helm,dnsmasq

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

  if [ "$(curl -sSf http://podinfo.traefik.minikube | jq -r '.message')" = "Hello from cluster. Check swagger at /swagger/index.html. I also have a secret, the api admin password is change-that-password" ]; then
    echo "Flux on minikube is ready"
  else
    echo "An error occured with flux or minikube, please check the logs. You might just need to wait a bit."
  fi
}

# Ensure to clean minikube cluster data from previous run, stored in the volume
minikube delete
(cd ~/.minikube && for file in *; do [ ! "$file" = "cache" ] && rm -rf ./"$file"; done)

debug_param=
[ "$DEBUG_FULL" -eq 1 ] && debug_param="--debug-full"

if ./start.sh --minikube --docker-services portainer,gitea,helm $debug_param; then
  echo "minikube cluster is ready"
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

# if ./start.sh --kind --flux "" $debug_param; then
#   echo "kind cluster is ready"
# else
#   echo "An error occured with minikube, please check the logs"
# fi

cat <<EOM


Here are some usefull commands to interact with the localarch container:

- check the logs: docker logs -f localarch
- connect to localarch container: docker exec -it localarch bash
  - run minikube cluster: ./start.sh --minikube --flux-path k8s/flux-playground/traefik-minikube --minikube-addons "ingress ingress-dns" --minikube-dns 1 --docker-services gitea,helm,dnsmasq --debug-full
  - run kind cluster (does not work yet): ./start.sh --kind --debug-full
  - check all resource on cluster: kubectl get all -A
  - check all kind of resources on cluster: kubectl api-resources --sort-by name
  - check minikube cluster: k9s -A --context minikube -c deployment
  - check kind cluster: k9s -A --context kind-kind -c deployment
  - check whoami: curl -sSf http://whoami.traefik.minikube
  - check podinfo: curl -sSf http://podinfo.minikube

EOM

tail -f /dev/null
