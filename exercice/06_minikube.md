# Minikube

## Start cluster

```shell
# Make sure to have host.minikube.internal resolving to localhost
grep -q 'host.minikube.internal' /etc/hosts || sed -r -e "/localhost\$/a 127.0.0.1       host.minikube.internal" /etc/hosts | sudo sponge /etc/hosts

minikube start --embed-certs --insecure-registry=host.minikube.internal:5007
kubectl config use-context minikube

# Retrieve minikube cluster config to add it to lens
cat ~/.kube/config | yq -o json | jq '.clusters |= [(.[] | select(.name == "minikube"))] | .contexts |= [(.[] | select(.name == "minikube"))] | .users |= [(.[] | select(.name == "minikube"))]' > ~/.kube/minikube.config
# Retrieve path to config and add it to Lens
wslpath -w ~/.kube/minikube.config
```

## Simple podinfo service

1. Kubectl commands

   ```shell
   kubectl create namespace info
   kubectl annotate namespace info local/hostname="$(hostname)"
   kubectl label namespace info local/user="$USER"
   kubectl --namespace info create deployment --replicas 1 --port 9898 --image stefanprodan/podinfo podinfo
   kubectl --namespace info expose deployment podinfo --type ClusterIP --port 9898
   kubectl --namespace info create ingress --class nginx --rule 'podinfo.minikube/*=podinfo:9898' minikube-podinfo

   # delete all
   kubectl delete namespace info
   ```

1. Manifests

   ```shell
   # Dry run to generate manifest
   kubectl create --dry-run=client -o yaml deployment --replicas 1 --port 9898 --image stefanprodan/podinfo podinfo

   . ./k8s/podinfo/setup_podinfo.sh

   # Simple manifests
   create_podinfo_manifest_with_metada k8s/podinfo/manifests
   kubectl apply -f k8s/podinfo/manifests/namespace.yaml
   kubectl apply --namespace info -f k8s/podinfo/manifests/deployment.yaml
   kubectl apply --namespace info -f k8s/podinfo/manifests/service.yaml
   kubectl apply --namespace info -f k8s/podinfo/manifests/ingress.yaml

   # Kustomization manifests
   create_kustomization k8s/podinfo/kustomization
   kubectl kustomize ./k8s/podinfo/kustomization/kustom
   kubectl apply -k ./k8s/podinfo/kustomization/kustom

   # delete all
   kubectl delete namespace info kustom-info

   # Full setup
   ./k8s/podinfo/setup_podinfo.sh
   ```

1. Port forwarding

   ```shell
   kubectl port-forward -n info --address 0.0.0.0 services/podinfo 49898:9898
   ```

   Open <http://localhost:49898/>

1. Dns

   Check dnsmasq there <http://localhost:3053/> and ensure to have the content returned by the following command:

   ```shell
   cat <<EOM
   listen-address=127.0.0.1
   bind-interfaces
   interface=lo
   port=53
   server=/minikube/$(minikube ip)
   EOM
   ```

   ```shell
   # Add minikube addons
   minikube addons enable ingress
   minikube addons enable ingress-dns

   curl -fsSL http://podinfo.minikube
   nslookup podinfo.minikube
   nslookup podinfo.minikube "$(minikube ip)"

   # Add "nameserver 127.0.0.1" at begining of /etc/resolv.conf
   if ! grep -qE '^nameserver 127.0.0.1' /etc/resolv.conf; then
     owner=$(stat -c "%U:%G" /etc/resolv.conf)
     (
       printf "# Added by %s at %s\n" "$USER" "$(date)"
       printf "nameserver 127.0.0.1\n"
       cat /etc/resolv.conf
     ) | sudo sponge /etc/resolv.conf
     sudo chown "$owner" /etc/resolv.conf
   fi

   nslookup podinfo.minikube
   curl -fsSL http://podinfo.minikube
   ```

   For fun, you can try to setup the dns to have google.com pointing to podinfo service.

## Docker image registry listener

```shell
# Build dkd docker image
./dkd/docker-build.sh

# Deploy it in the cluster
kubectl apply -k ./k8s/dkd
kubectl logs -f -n dkd deployments/dkd
docker logs -f docker-registry

docker exec -ti docker-registry sh -c "echo '$(minikube ip) dkd.minikube' >> /etc/hosts"
docker network connect minikube docker-registry

docker push "localhost:5007/dkd"
```
