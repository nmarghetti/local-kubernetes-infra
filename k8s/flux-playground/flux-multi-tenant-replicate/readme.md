# Flux multi tenant

Based on <https://github.com/fluxcd/flux2-multi-tenancy>.

```shell
# Run for minikube
./start.sh --minikube --flux-path k8s/flux-playground/flux-multi-tenant-replicate/clusters/minikube --docker-services gitea
# Run for kind
./start.sh --kind --flux-path k8s/flux-playground/flux-multi-tenant-replicate/clusters/kind --docker-services gitea
```

You can then check the status of the kustomization:

```shell
# you will see that the team-bar fails because it tries to modify foo namespace
# you would also see other errors if you run it with kind as it tries to update foo-minikube namespace
flux get kustomization -A
```

You can apply some role to check RBACs and use [this kubeconfig](../../../tmp/minikube-user_kubeconfig.yaml).

```shell
# Add view RBACs to foo namespace
kubectl create rolebinding team-foo-member-view-binding --role=foo-view --user="$USER" --namespace=foo --dry-run=client -o yaml | kubectl apply -f -
```

Check this link to create flux tenant: <https://fluxcd.io/flux/cmd/flux_create_tenant/>.

To create the tenants:

```shell
./scripts/flux_setup_tenants.sh k8s/flux-playground/flux-multi-tenant-replicate/tenants.json
```
