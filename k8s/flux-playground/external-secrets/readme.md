# External secrets

```shell
./start.sh --minikube --flux-path k8s/flux-playground/external-secrets/flux-system --docker-services gitea,helm

# Check generated secret
./scripts/check_external_secret.sh --cluster minikube --app podinfo --namespace mychart-podinfo --store fake-config-templated --config mychart-podinfo-podinfo-secret-config

# Check secret being injected into podinfo
pod=$(kubectl get pods -n mychart-podinfo -l app.kubernetes.io/name=mychart -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' 2>/dev/null)
kubectl exec -t -n mychart-podinfo "$pod" -- curl -sSf http://localhost:9898 | jq -r '.message'
# You should see the admin api password in the message
```

## Misc

```shell
# Get last secret sync
kubectl get ExternalSecret -n mychart-podinfo mychart-podinfo-podinfo-secret -o jsonpath='{.status.conditions[0]}' | jq
# Debug secret status
kubectl describe ExternalSecret -n mychart-podinfo mychart-podinfo-podinfo-secret
# Force sync external secret
kubectl annotate ExternalSecret -n mychart-podinfo mychart-podinfo-podinfo-secret force-sync=$(date +%s) --overwrite
# Force sync all external secrets from a given namespace (eg. mychart-podinfo)
kubectl annotate ExternalSecret -n mychart-podinfo --all force-sync=$(date +%s) --overwrite
# Get all secrets from helm chart for a given namespace (eg. mychart-podinfo)
kubectl get -n mychart-podinfo secrets -l chart-secret-source=external-secrets -o jsonpath='{.items[*].metadata.name}' | xargs echo
# Force sync all secrets from helm for a given namespace (eg. mychart-podinfo)
kubectl annotate ExternalSecret -n mychart-podinfo -l helm.toolkit.fluxcd.io/namespace=mychart-podinfo force-sync=$(date +%s) --overwrite
```
