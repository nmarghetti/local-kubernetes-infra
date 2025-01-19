#! /bin/bash

cd "$(dirname "$(readlink -f "$0")")" || {
  echo "Unable to go to parent folder of $0" >&2
  exit 1
}

SCRIPTS=$(git rev-parse --show-toplevel)/scripts
# shellcheck source=../../../../../scripts/common.sh
. "$SCRIPTS"/common.sh

certs_path=.

cp -f /etc/ssl/certs/ca-certificates.crt "$certs_path"/ca-certificates.crt
for cluster in minkibue kind; do
  ca_name="${cluster}CA"
  ca_crt="$GIT_ROOT/tmp/${cluster}_ca.crt"
  [ -f "$ca_crt" ] && cat <<EOM >>"$certs_path"/ca-certificates.crt

$ca_name
=====================================
$(cat "$ca_crt")
EOM
done
