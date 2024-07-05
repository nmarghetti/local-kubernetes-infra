# Flux multi tenant

Based on <https://github.com/fluxcd/flux2-multi-tenancy>.

```shell
./start.sh --minikube --flux-path k8s/flux-playground/flux-multi-tenant/cluster --docker-services gitea
```

You can then check the status of the kustomization, you will see that the team-bar fails because it tries to modify foo namespace:

```shell
flux get kustomization -A
```
