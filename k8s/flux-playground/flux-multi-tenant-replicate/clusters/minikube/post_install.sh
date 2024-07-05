#! /bin/sh

cd "$(dirname "$(readlink -f "$0")")" || {
  echo "Unable to go to parent folder of $0" >&2
  exit 1
}

# If for some reason minikube is not able to pull the image from quay.io, you can uncomment
# if ! curl -sS http://localhost:5007/v2/mittwald/kubernetes-replicator/tags/list 2>/dev/null | jq '.tags' | grep -q '"v2.11.0"'; then
#   docker pull quay.io/mittwald/kubernetes-replicator:v2.11.0
#   docker tag quay.io/mittwald/kubernetes-replicator:v2.11.0 localhost:5007/mittwald/kubernetes-replicator:v2.11.0
#   docker push localhost:5007/mittwald/kubernetes-replicator:v2.11.0
# fi

# You need to duplicate the secret to access git repository for each tenant
# Add annotations for the replicator to do it
namespaces=$(ls -1 ./tenant | tr '\n' ',')
namespaces=${namespaces%,}
kubectl annotate secret flux-system -n flux-system replicator.v1.mittwald.de/replicate-to="${namespaces}" --overwrite
