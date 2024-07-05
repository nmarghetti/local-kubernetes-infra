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
if find . -type f -name "*.crt" -exec basename {} \; | grep -vE '^'"$bundle_name"'$' | grep -q crt; then
  mkdir -p ~/.minikube/certs
  for file in $(find . -type f -name "*.crt" -exec basename {} \; | grep -vE '^'"$bundle_name"'$' | sort); do
    file_path="./$file"
    if [ ! -f "$HOME/.minikube/certs/$file" ] || ! cmp "$HOME/.minikube/certs/$file" "$file_path"; then
      cp -vf "$file_path" "$HOME/.minikube/certs/$file"
    fi
  done
fi

exit 0
