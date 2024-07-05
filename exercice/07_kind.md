# Kind

## Start cluster

```shell
# Create kind config
kind_config=$(mktemp)
cat <<EOM >"$kind_config"
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  # WARNING: It is _strongly_ recommended that you keep this the default
  # (127.0.0.1) for security reasons. However it is possible to change this.
  # apiServerAddress: "127.0.0.1"
  # By default the API server listens on a random open port.
  # You may choose a specific port but probably don't need to in most cases.
  # Using a random port makes it easier to spin up multiple clusters.
  # apiServerPort: 6443
nodes:
- role: control-plane
  kubeadmConfigPatches:
    - |
      kind: InitConfiguration
      nodeRegistration:
        kubeletExtraArgs:
          node-labels: "ingress-ready=true"
  extraPortMappings:
    - containerPort: 80
      hostPort: ${KIND_HTTP_PORT:-80}
      protocol: TCP
    - containerPort: 443
      hostPort: ${KIND_HTTPS_PORT:-443}
      protocol: TCP
  extraMounts:
   - hostPath: $(pwd)/certificates
     containerPath: /usr/local/share/ca-certificates/corporate
- role: worker
  extraMounts:
   - hostPath: $(pwd)/certificates
     containerPath: /usr/local/share/ca-certificates/corporate
- role: worker
  extraMounts:
   - hostPath: $(pwd)/certificates
     containerPath: /usr/local/share/ca-certificates/corporate
EOM

kind create cluster --config "$kind_config"
for node in $(kind get nodes); do
  # Ensure it is started
  docker container start "$node" >/dev/null
  # Ensure it does not restart with host reboot
  docker update --restart=no "$node" >/dev/null
  # Ensure to have certificates
  docker exec -it "$node" /bin/bash -c 'update-ca-certificates'
done
kubectl config use-context "$(kind get kubeconfig | yq '.current-context')"

# Make sure to have host.kind.internal resolving to localhost
grep -q "host.kind.internal" /etc/hosts || sed -r -e "/localhost\$/a 127.0.0.1       host.kind.internal" /etc/hosts | sudo sponge /etc/hosts

# Ensure the cluster has connectivity
HOST_IP=$(ip addr show docker0 | awk '/inet / {print $2}' | cut -d/ -f1)
docker exec -it kind-control-plane timeout 2 bash -c "</dev/tcp/${HOST_IP}/3000"

# Retrieve kind cluster config to add it to lens
kind export kubeconfig --kubeconfig ~/.kube/kind.config
# Retrieve path to config and add it to Lens
wslpath -w ~/.kube/kind.config
```

## Flux

```shell
# Setup git
gitea_token=$(docker exec -t gitea bash -c "cat /data/token | xargs printf '%s'")
git remote add -m main gitea url
git remote set-url gitea "http://${gitea_token}@host.kind.internal:3000/gitadmin/local_cluster.git"
git push --quiet --force gitea main

# bootstrap
flux bootstrap git --silent --branch=main --path=k8s/$USER --ca-file=./certificates/ca-bundle.crt --token-auth --allow-insecure-http --url=http://${HOST_IP}:3000/gitadmin/local_cluster.git < <(echo "$gitea_token")
git pull gitea main --rebase
```
