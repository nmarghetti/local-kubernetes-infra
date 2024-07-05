# Kubernetes

<https://kubernetes.io/docs/concepts/overview/components/>

![image](components-of-kubernetes.svg)

- Control Plane Components
  - kube-apiserver: Exposes the Kubernetes API and handles requests from users and other components.
  - etcd: Consistent and highly-available key-value store for cluster data.
  - kube-scheduler: Watches for newly created Pods and assigns them to nodes based on resource requirements and constraints.
  - kube-controller-manager: Manages various controllers (e.g., node controller, job controller) to maintain desired cluster state.
- Worker Nodes:
  - kubelet: Ensures containers are running in a Pod.
  - kube-proxy: Maintains network rules for communication between Pods.
  - Container Runtime: Executes containers (e.g., Docker, containerd).

You can check the clusters and contexts available on your machine:

```shell
# Check clusters and context available
kubectl config get-clusters
kubectl config get-contexts
```
