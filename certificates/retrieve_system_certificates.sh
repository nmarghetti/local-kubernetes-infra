#! /bin/sh

cd "$(dirname "$(readlink -f "$0")")" || {
  echo "Unable to go to parent folder of $0" >&2
  exit 1
}

SCRIPTS=$(git rev-parse --show-toplevel)/scripts
# shellcheck source=../scripts/common.sh
. "$SCRIPTS"/common.sh

bundle=./ca-bundle.crt
bundle_name=$(basename "$bundle")
ignore_cert="($bundle_name|local_.*|mkcert.*|kind.*|minikube.*)"
# If there is no certificate in the current folder yet
if ! find . -type f -name "*.crt" -exec basename {} \; | grep -vE '^'"$bundle_name"'$' | grep -q crt; then
  find /usr/local/share/ca-certificates -type f -name "*.crt" | while IFS= read -r cert; do
    if basename "$cert" | grep -vE '^'"$ignore_cert"'$' | grep -q crt; then
      cp -vf "$cert" .
    fi
  done
fi

exit 0
