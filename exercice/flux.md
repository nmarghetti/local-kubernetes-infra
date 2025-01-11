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


# Image automation
# suspend the full image automation
flux suspend image update flux-system
# suspend only one
flux suspend image repository podinfo
# resume
flux resume image update flux-system


# Wait for all flux kustomization to reconcile
# leave extra_args empty if it does not need to fetch git repository
extra_args='--with-source'
while read -r line; do
  # shellcheck disable=SC2086
  set $line
  echo "Waiting for $1/$2 to reconcile..."
  flux reconcile kustomization -n "$1" "$2" $extra_args --timeout 5m
  echo
done < <(kubectl get -A kustomizations.kustomize.toolkit.fluxcd.io --no-headers -o custom-columns=NAME:.metadata.namespace,RSRC:.metadata.name)
unset extra_args
```
