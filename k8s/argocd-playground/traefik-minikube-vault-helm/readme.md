# Traefik, minikube, vault, helm

This is a complete showcase of:

- external-secrets.io to access secrets from a vault to avoid having any secret in the git repository
- locally built helm to packages many services and ease accessing the secrets from the vault
- traefik to access the different services

```shell
# Here is the command to run the minimum needed for this playground to work
PODINFO_UI_MESSAGE='Hello from minikube local cluster' ./start.sh --minikube --minikube-addons "ingress ingress-dns" --minikube-dns 1 --argocd-path ./k8s/argocd-playground/traefik-minikube-vault-helm/argocd --docker-services gitea,registry,helm,dnsmasq

# To access argocd from https://localhost:8080/ with user admin and password Y0NfZtbDAm9Yv3jz
kubectl port-forward svc/argocd-server -n argocd 8080:80

# You can then check podinfo message
curl -sSf http://podinfo.minikube | jq -r '.message'
curl -sSf http://podinfo.traefik.minikube | jq -r '.message'
```

From browser started from WSL, you can check <http://home.minikube/> and <http://argocd.traefik.minikube/>.
