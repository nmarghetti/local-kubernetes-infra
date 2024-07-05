#! /bin/sh

cd "$(dirname "$(readlink -f "$0")")" || {
  echo "Unable to go to parent folder of $0" >&2
  exit 1
}

# Either you can duplicate the secret manually
tmpfile=$(mktemp)
kubectl get secret flux-system -n flux-system -o yaml | sed -re '/namespace:/d' >"$tmpfile"
for namespace in ./tenant/*; do
  namespace=$(basename "$namespace")
  kubectl apply -f "$tmpfile" -n "$namespace" >/dev/null 2>&1
done
rm "$tmpfile"
