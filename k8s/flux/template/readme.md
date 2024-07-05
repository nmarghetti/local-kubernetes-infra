# Flux

Here is the sequence of kustomization:

- flux-system
- crds
- vault-core
- vault
- infrastructure-core
- infrastructure
- application-core
- application

## Flux upgrade

```shell
flux uninstall -s
curl -sS https://fluxcd.io/install.sh | sudo FLUX_VERSION=2.2.3 bash
flux install --export > ./flux-system/gotk-components.yaml
# Ensure api version are fine in ./flux-system/gotk-sync.yaml and ./flux-system/kustomization.yaml
kubectl kustomize ./flux-system
kubectl apply -k ./flux-system
```
