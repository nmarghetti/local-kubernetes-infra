# Local kubernetes infrastructure

## Init repository

```shell
# Init submodules
git submodule update --init
cd scripts/utils &&
  git sparse-checkout set --no-cone '/log.sh' &&
  cd -
cd helm &&
  for submodule in $(git submodule | awk '{ print $2 }'); do if [ -e "$submodule" ]; then git submodule deinit -f "$submodule" 2>/dev/null; fi; done &&
  git sparse-checkout set --no-cone '/generic-chart' '/tests' '/README.md' &&
  cd -

# Upgrade submodules
git submodule update --remote
```

## Setup

1. Prerequesites

   You need to be under WSL2 Ubuntu 24.04 and have several tools installed:

   - docker
   - minikube, kind, kubectl
   - curl, jq, yq, moreutils, netcat, ip

   You can run this command to install it:

   ```shell
   ./scripts/setup_deps.sh
   ```

1. Certificates configuration
   You might be behind an enterprise proxy or VPN and need to add some certificates to WSL in order to avoid connection issue. In that case, ask for those certificates, put them under `/usr/local/share/ca-certificates/` folder and run the following command `update-ca-certificates`.

   You can check that the following command run well:

   ```shell
   openssl s_client -connect google.com:443 </dev/null
   # Show all certificates in chain
   openssl s_client -connect google.com:443 -showcerts 2>/dev/null </dev/null | sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' >./bundle.crt
   openssl storeutl -noout -text -certs ./bundle.crt
   ```

1. Exercices

   If you want to understand better what it behind the scene, you can do the following exercices:

   - [certificates](exercice/01_certificates.md)
   - [docker](exercice/02_docker.md)
   - [gitea](exercice/03_gitea.md)
   - [services](exercice/04_services.md)
   - [kubernetes_overview](exercice/05_kubernetes_overview.md)
   - [minikube](exercice/06_minikube.md)
   - [kind](exercice/07_kind.md)
   - [flux](exercice/08_flux.md)
   - [argocd](exercice/09_argocd.md)
   - [harness](exercice/10_harness.md)

1. Local services with docker compose

   Some of the following services will be ran with docker compose when running some playgrounds.

   - portainer: overview of your docker (image, container, volumes, etc.) available at <http://localhost:9400/#!/2/docker/containers> with admin/F0jJ7XWo1TJKyhLQJ62Y
   - nginx: a simple local http server that only serve an html pages with links to access to the different services, available at <http://localhost>
   - traefik: reverse proxy that allows to have access nginx service under <http://localhost> and other docker compose services under `*.docker.localhost`. Its dashboard for more details is available at <http://localhost:8080/> with admin/traefik
   - gitea: git server available at <http://localhost:3000/gitadmin/local_cluster> with gitadmin/v6ccouGZLBogfMn1AzL7
   - helm registry: to store helm artifact that you can check at <http://localhost:8088/api/charts>
   - docker-registry: to store docker image
   - docker-registry-ui: UI for the docker registry available at <http://localhost:8087/>
   - podinfo: simple webserver/api available at <http://localhost:9898/> with swagger at <http://localhost:9898/swagger/index.html>
   - dnsmasq: dns server with UI available at <http://localhost:3053/> with admin/dnsmasq
   - harness: harness open source available at <http://localhost:3200/>.

   You can run them all with the following command knowing that it will be run anyway with playing with the playground:

   ```shell
   ./scripts/setup_docker_compose_services.sh
   # Check the logs to learn some commands to check the different services
   ```

   You can also secure the services with certificates to use https (it is not fully working yet with the cluster, so better avoid it so far):

   ```shell
   ./scripts/setup_docker_compose_services.sh --use-ssl
   # Check the logs to learn some commands to check the different services

   # the script above would regenerate the certificates if expired with the following command
   ./docker-compose/generate_certificates.sh
   ```

1. Playground

   1. portainer

      ```shell
      # You can simply start portainer container with one of the following commands:
      ./scripts/setup_docker_compose_services.sh --docker-services portainer
      ./start.sh --docker-services portainer
      ```

   1. minikube

      ```shell
      # Start an empty minikube cluster
      ./start.sh --minikube
      # Start minikube cluster with dns
      ./start.sh --minikube --minikube-addons ingress,ingress-dns --minikube-dns

      # Retrieve minikube cluster config to add it to lens
      # cat ~/.kube/config | yq -o json | jq '.clusters |= [(.[] | select(.name == "minikube"))] | .contexts |= [(.[] | select(.name == "minikube"))] | .users |= [(.[] | select(.name == "minikube"))]' > ~/.kube/minikube.config
      kubectl config view --minify --raw > ~/.kube/minikube.config
      # Retrieve path to config and add it to Lens
      wslpath -w ~/.kube/minikube.config

      # Or start the dashboard
      minikube dashboard
      ```

      Check [this playground](k8s/flux-playground/traefik-minikube/readme.md) to access minikube cluster resources from <http://home.traefik.minikube/> (it works only from a browser started from WSL).

   1. kind

      ```shell
      # Start an empty kind cluster
      ./start.sh --kind

      # Retrieve kind cluster config to add to lens
      kind export kubeconfig --kubeconfig ~/.kube/kind.config
      # Retrieve path to config and add it to Lens
      wslpath -w ~/.kube/kind.config
      ```

      Check [this playground](k8s/flux-playground/traefik-kind/readme.md) to:

      - access kind cluster resources from <http://localhost>
      - play with node affinity and pod anti affinity.

1. Reset everything

   Simply run the following command to delete all docker container/volume and local cluster.

   ```shell
   ./reset.sh
   ```

## Docker in docker

To ensure that it does not only work on my machine, it can be ran inside docker. So far it works with minikube but not kind.

```shell
# To debug the docker build
DOCKER_BUILDKIT=0 ./docker_build.sh 2>&1 | tee ./tmp/docker_output.log

# Deploy the minikube cluster with dashboard and few services
./docker_build.sh --minikube-dashboard --services nginx,traefik --debug-full 0

# Simple scenario with traefik
./docker_build.sh --scenario traefik-minikube

# More complex scenario with vault, local helm and traefik
./docker_build.sh --scenario traefik-minikube-vault-helm --clean registry --docker-services gitea,registry,registry-ui,helm,dnsmasq,dkd,nginx,traefik
# Check http://localhost:30000

# Check the logs of localarch
docker logs -f localarch

# Check minikube kubernetes server replies
docker exec -ti localarch curl -k https://127.0.0.1:32771/version
# Check minikube kubernetes server access from traefik
curl -H 'Host: k8s.localhost' https://localhost:30000/version
```

## Access minikube cluster from Lens

1. minikube cluster

   ```shell
   # start minikube with nginx and traefik services
   ./start.sh --minikube --docker-services nginx,traefik
   ```

   You can add a cluster to Lens with content of [minikube_kubeconfig.yaml](tmp/minikube_kubeconfig.yaml).

1. minikube cluster inside localarch docker container

   ```shell
   # build localarch with nginx and traefik services
   ./docker_build.sh --services nginx,traefik
   ```

   You can add a cluster to Lens with content of [minikube_localarch_kubeconfig.yaml](tmp/minikube_localarch_kubeconfig.yaml).

## Troubleshooting

1. Minikube

   ```shell
   # In case minikube takes too long to start, delete it first
   minikube delete
   docker network rm minikube
   ```

1. 10.255.255.254 address already in use

   ```shell
   # check you network interfaces
   ip addr show
   # delete 10.255.255.254 from lo interface
   sudo ip addr del 10.255.255.254/32 dev lo
   ```

1. Certificates errors on websites under WSL

   Add your certificates in you web browser trusted Authorities.
