# Traefik

This playground with kind allows to spawn several nodes and play with the node affinity and pod anti affinity.
It illustrates:

- how to choose on which node a pod would be deployed
- how to avoid a pod to be schedule on a node where it is already present

It also use traefik to access some resources on the cluster directly from localhost.

## Run

```shell
# Here is the command to run the minimum needed for this playground to work
./start.sh --kind --flux-path k8s/flux-playground/traefik-kind --docker-services "gitea"
```

You can then check <http://localhost>.

## Node affinity

```shell
# Check all pods
kubectl get pods -n playground-traefik-kind -o wide

# You can see that there is:
# - one traefik pod per node as it is deployed with daemonset
# - podinfo on node kind-worker2 as asked
# - no whoami pod deployed on kind-worker2 as asked
```

## Pod anti afiinity

```shell
# Increase number of whoami pods
kubectl scale deployment whoami --replicas=3 -n playground-traefik-kind
# Check the pods
kubectl get pods -l app=whoami -n playground-traefik-kind -o wide --watch
# Check the status of pods that are not running
kubectl get pods --field-selector=status.phase!=Running -n playground-traefik-kind
# Describe a specific pod that is not running
kubectl describe pod "$(kubectl get pods --field-selector=status.phase!=Running -n playground-traefik-kind --no-headers | head -1 | awk '{ print $1 }')" -n playground-traefik-kind

# You would see that it cannot be scheduled as it does not match the pod anti affinity
```
