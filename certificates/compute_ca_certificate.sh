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
  printf "" >"$bundle"
  for file in $(find . -type f -name "*.crt" -exec basename {} \; | grep -vE '^'"$bundle_name"'$' | sort); do
    file_path="./$file"
    {
      printf "%s\n=====================================\n" "${file%.*}"
      cat "$file_path"
      printf "\n"
    } >>"$bundle"
  done
  log_info "Certificate bundle created at $(readlink -f "$bundle")"
  # openssl storeutl -noout -text -certs "$bundle"
else
  bundle=/etc/ssl/certs/ca-certificates.crt
fi

[ ! -f "$bundle" ] && exit_error "Unable to find a certificate bundle to use"

exit 0

# cpt=0
# while [ $cpt -le 10 ] && ! kubectl get namespace "flux-system" >/dev/null 2>&1; do
#   cpt=$((cpt + 1))
#   sleep 5
# done
# [ $cpt -ge 10 ] && exit_error "Unable to create certificate_authority secret for flux-system"

kubectl delete secret -n flux-system certificate-authority >/dev/null 2>&1
# kubectl create secret -n flux-system generic certificate-authority --from-file=ca.crt="$bundle"
find . -type f -name "*.crt" -exec basename {} \; | grep -vE '^'"$bundle_name"'$' | grep crt | sed -re 's/^(.+)$/ --from-file=\1=\1/' | tr '\n' ' ' |
  xargs kubectl create secret -n flux-system generic certificate-authority --from-file=ca.crt="$bundle"
