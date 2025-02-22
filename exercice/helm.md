# Helm

## Package

```shell
# Ensure to have local helm registry available
./start.sh --docker-services helm

# Build and push
./scripts/build_helm.sh

# Get helm chart
curl -sS http://localhost:8088/api/charts/mychart/1.0.0 | jq
```

## Install full example

First you need to start [this playground](../k8s/flux-playground/traefik-minikube-vault-helm/readme.md).

```shell
./start.sh --minikube --flux-path k8s/flux-playground/traefik-minikube-vault-helm --minikube-addons "ingress ingress-dns" --minikube-dns --docker-services gitea,helm,dnsmasq
```

Then you can play with the helm and install it in another namespace.

```shell
# Get values from playground
kubectl kustomize k8s/flux-playground/traefik-minikube-vault-helm/application/mychart | yq '. | select(.kind == "HelmRelease") | .spec.values' > ./helm/examples/values-flux-playground_traefik-minikube-vault-helm.yaml
# Install
helm install --create-namespace -n example --values ./helm/examples/values-flux-playground_traefik-minikube-vault-helm.yaml apps ./helm
# Update
helm upgrade --create-namespace -n example --values ./helm/examples/values-flux-playground_traefik-minikube-vault-helm.yaml apps ./helm
# Uninstall
helm uninstall -n example apps
```
