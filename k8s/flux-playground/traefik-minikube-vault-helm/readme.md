# Traefik, minikube, vault, helm

This is a complete showcase of:

- external-secrets.io to access secrets from a vault to avoid having any secret in the git repository
- locally built helm to packages many services and ease accessing the secrets from the vault
- traefik to access the different services

```shell
# Here is the command to run the minimum needed for this playground to work
PODINFO_UI_MESSAGE='Hello from minikube local cluster' ./start.sh --minikube --flux-path k8s/flux-playground/traefik-minikube-vault-helm --minikube-addons "ingress ingress-dns" --minikube-dns 1 --docker-services gitea,helm,dnsmasq

# You can then check podinfo message
curl -sSf http://podinfo.minikube | jq -r '.message'
curl -sSf http://podinfo.traefik.minikube | jq -r '.message'
```

From browser started from WSL, you can check <http://home.traefik.minikube/>.
