# Traefik

```shell
helm repo add traefik https://traefik.github.io/charts
helm repo udpate
helm install -f ./k8s/helm/traefik/values.yaml -n traefik traefik oci://ghcr.io/traefik/helm/traefik
helm upgrade -f ./k8s/helm/traefik/values.yaml -n traefik traefik traefik/traefik
helm uninstall -n traefik traefik
```
