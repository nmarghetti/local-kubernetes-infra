# Traefik, minikube, vault, helm

This is a complete showcase of:

- external-secrets.io to access secrets from a vault to avoid having any secret in the git repository
- locally built helm to packages many services and ease accessing the secrets from the vault
- traefik to access the different services

```shell
# Here is the command to run the minimum needed for this playground to work
PODINFO_UI_MESSAGE='Hello from minikube local cluster' ./start.sh --minikube --flux-image-automation --flux-path k8s/flux-playground/traefik-minikube-vault-helm --minikube-addons "ingress ingress-dns" --minikube-dns 1 --docker-services gitea,registry,registry-ui,helm,dnsmasq,dkd

# You can then check podinfo message
curl -sSf http://podinfo.minikube | jq -r '.message'
curl -sSf http://podinfo.traefik.minikube | jq -r '.message'

# Build another image to see automatic update
./docker/docker-build.sh flux-automated 2024-12-27-08-00.0
./docker/docker-build.sh myproject-automated 2.0.0

# Trigger the webhook to it will update the images
webhook=$(kubectl get -n flux-system receivers.notification.toolkit.fluxcd.io apps -o jsonpath='{.status.webhookPath}')
url="http://webhook-receiver.flux-system.svc.cluster.local${webhook}"
pod=$(kubectl get pods -n flux-system -l app.kubernetes.io/component=curl -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' 2>/dev/null)
kubectl exec -t -n flux-system "$pod" -- curl -sSf -X POST "$url" -H 'accept: application/json' -H 'Content-Type: application/json' -d '{"events": []}'

# Check gitea
git fetch gitea main
git show gitea/main | less
```

From browser started from WSL, you can check <http://home.traefik.minikube/>.
