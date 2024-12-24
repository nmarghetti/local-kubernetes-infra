#! /bin/sh

cd "$(dirname "$(readlink -f "$0")")" || {
  echo "Unable to go to parent folder of $0" >&2
  exit 1
}

# You need to duplicate the certificates for external secrets
# Add annotations for the replicator to do it
kubectl annotate configmap certificates -n flux-system replicator.v1.mittwald.de/replicate-to="external-secrets" --overwrite
