# Traefik, minikube, vault, helm

This is a complete showcase of:

- external-secrets.io to access secrets from a vault to avoid having any secret in the git repository
- locally built helm to packages many services and ease accessing the secrets from the vault
- traefik to access the different services

```shell
# Here is the command to run the minimum needed for this playground to work
PODINFO_UI_MESSAGE='Hello from minikube local cluster' ./start.sh --minikube --gitea-webhook --flux-image-automation --flux-path k8s/flux-playground/traefik-minikube-vault-helm --minikube-addons "ingress ingress-dns" --minikube-dns --docker-services gitea,registry,registry-ui,helm,dnsmasq,dkd,nginx,traefik

# You can then check podinfo message
curl -sSf http://podinfo.minikube | jq -r '.message'
curl -sSf http://podinfo.traefik.minikube | jq -r '.message'

# Build another image to see automatic update
./docker/docker-build.sh flux-automated 2024-12-27-08-00.0
./docker/docker-build.sh myproject-automated 2.0.0

# The update of the image should be automatic with hook from docker registry and flux notification but you can still trigger it manually

# Trigger the webhook so it will update the images
webhook=$(kubectl get -n flux-system receivers.notification.toolkit.fluxcd.io apps -o jsonpath='{.status.webhookPath}')
url="http://webhook-receiver.flux-system.svc.cluster.local${webhook}"
pod=$(kubectl get pods -n flux-system -l app.kubernetes.io/component=curl -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' 2>/dev/null)
kubectl exec -t -n flux-system "$pod" -- curl -sSf -X POST "$url" -H 'accept: application/json' -H 'Content-Type: application/json' -d '{"events": []}'

# You can also trigger the webhook through flux-webhook.traefik.minikube
curl -sSf -X POST "http://flux-webhook.traefik.minikube${webhook}" -H 'accept: application/json' -H 'Content-Type: application/json' -d '{"events": []}'

# If you add traefik,nginx to --docker-services, you can even trigger it from localhost
curl -sSf -X POST "http://localhost${webhook}" -H 'Host: traefik' -H 'accept: application/json' -H 'Content-Type: application/json' -d '{"events": []}'

# Check gitea
git fetch gitea main
git show gitea/main | less
```

From your browser, check <http://localhost>.

If not working, from browser started from WSL, you can check <http://home.traefik.minikube/>.
