# Traefik

```shell
# Here is the command to run the minimum needed for this playground to work
PODINFO_UI_MESSAGE='Hello from minikube local cluster' ./start.sh --minikube --flux-path k8s/flux-playground/traefik-minikube --minikube-addons "ingress ingress-dns" --minikube-dns --docker-services gitea,dnsmasq

# You can then check podinfo message
curl -sSf http://podinfo.minikube | jq -r '.message'
curl -sSf http://podinfo.traefik.minikube | jq -r '.message'
```

From browser started from WSL, you can check <http://home.traefik.minikube/>.
