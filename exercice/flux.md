# Flux

```shell
# Reconciliate
flux reconcile kustomization flux-system --with-source

# If reconciliation is not working
# - save flux-system secret and certificates config
kubectl get secrets -n flux-system flux-system -o yaml | yq 'del(.metadata.uid,.metadata.creationTimestamp,.metadata.resourceVersion)' >tmp/flux-system-secret.yaml
kubectl get configmaps -n flux-system certificates -o yaml | yq 'del(.metadata.annotations,.metadata.uid,.metadata.creationTimestamp,.metadata.resourceVersion)' >tmp/flux-system-certifica
tes.yaml
# - retrieve path to kustomization
flux_path="$(kubectl get -n flux-system kustomizations.kustomize.toolkit.fluxcd.io flux-system -o yaml | yq '.spec.path')"
# - uninstall flux
flux uninstall --silent
# - wait for flux-system namespace to be termintated
# - reinstall flux
kubectl create namespace flux-system
kubectl apply -f tmp/flux-system-secret.yaml
kubectl apply -f tmp/flux-system-certificates.yaml
kubectl apply -k "$flux_path"/flux-system
```
