# Traefik, minikube, vault, helm

This is a complete showcase of:

- external-secrets.io to access secrets from a vault to avoid having any secret in the git repository
- locally built helm to packages many services and ease accessing the secrets from the vault
- traefik to access the different services
- multi tenants isolation: foo application not working as it tries to deploy in bar namespace

```shell
# Here is the command to run the minimum needed for this playground to work
./start.sh --minikube --argocd-path ./k8s/argocd-playground/multi-tenant/argocd --docker-services gitea

# To access argocd from http://localhost:8888/ with user admin and password Y0NfZtbDAm9Yv3jz
kubectl port-forward svc/argocd-server -n argocd 8888:80

```
