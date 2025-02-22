# Helm

## Package

```shell
# Ensure to have local helm registry available
./start.sh --docker-services helm

# Build and push
./scripts/build_helm.sh

# Get helm chart
chart_name='generic-chart'
chart_version=$(yq '.version' <"./helm/${chart_name}/Chart.yaml")
curl -sS "http://localhost:8088/api/charts/${chart_name}/${chart_version}" | jq
```

## Install full example

First you need to start [this playground](../k8s/flux-playground/traefik-minikube-vault-helm/readme.md).

```shell
./start.sh --minikube --flux-path k8s/flux-playground/traefik-minikube-vault-helm --minikube-addons "ingress ingress-dns" --minikube-dns --docker-services gitea,helm,registry,dnsmasq
```

Then you can play with the helm and install it in another namespace.

```shell
# Get values from playground
kubectl kustomize k8s/flux-playground/traefik-minikube-vault-helm/application/apps | yq '. | select(.kind == "HelmRelease") | .spec.values' > ./helm/tests/values-flux-playground_traefik-minikube-vault-helm.yaml
# Install
helm install --create-namespace -n example --values ./helm/tests/values-flux-playground_traefik-minikube-vault-helm.yaml apps ./helm
# Update
helm upgrade --create-namespace -n example --values ./helm/tests/values-flux-playground_traefik-minikube-vault-helm.yaml apps ./helm
# Uninstall
helm uninstall -n example apps
```
