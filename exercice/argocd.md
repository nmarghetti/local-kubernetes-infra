# Argocd

```shell
# Access UI at https://localhost:8080
kubectl port-forward svc/argocd-server -n argocd 8080:443
# User is admin, password can be found with
argocd admin initial-password -n argocd

# Ensure to have access to the argocd server
export ARGOCD_OPTS='--port-forward --port-forward-namespace argocd'

argocd --port-forward-namespace argocd login --insecure localhost:8080 --username admin --password "$(argocd admin initial-password -n argocd 2>/dev/null | head -1 | tr -d '\n')"

# argocd --port-forward-namespace argocd cluster add -y minikube

# kubectl config set-context --current --namespace=argocd

# Test app of app
argocd app create apps --repo https://github.com/argoproj/argocd-example-apps.git --path apps --dest-server https://kubernetes.default.svc --dest-namespace default
argocd app sync apps
```
