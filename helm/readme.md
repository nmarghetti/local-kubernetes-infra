# Helm chart

## Unit test

First ensure to install helm unit test plugin `helm plugin install https://github.com/quintush/helm-unittest --version v0.2.9`.
You can also update it with `helm plugin update unittest`.

You can get the templates list for `helm/tests/*_test.yaml` with `find helm/templates -name "*.yaml" -o -name "*.yml" | sort | sed -re 's#helm/templates/# - #'`

```shell
# test the helm chart
helm unittest ./helm
# update tha snapshots
helm unittest ./helm -u
```

## Check the helm

```shell
# Check the template generation
helm template ./helm --debug | yq '.'

# Check with values
helm template ./helm --values ./helm/tests/values-base.yaml --values ./helm/tests/values-enabled.yaml --values ./helm/tests/values-full.yaml --debug
helm template ./helm --values ./helm/examples/values-flux-playground_traefik-minikube-vault-helm.yaml --debug

# Lint the helm
helm lint ./helm
```

## Check installation

```shell
# Check the files embedded inside the helm, there should be none
helm install apps ./helm --dry-run --output json | jq -r '.chart.files[]?.name'
# Check the templates embedded inside the helm
helm install apps ./helm --dry-run --output json | jq -r '.chart.templates[].name'
# Check the full content
helm install apps ./helm --dry-run --output yaml | yq
# Check the full content with values
helm install apps ./helm --values ./helm/tests/values-enabled.yaml --values ./helm/tests/values-full.yaml --dry-run --output yaml | yq
```

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
