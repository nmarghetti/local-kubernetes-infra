#! /bin/bash

cd "$(dirname "$(readlink -f "$0")")" || {
  echo "Unable to go to parent folder of $0" >&2
  exit 1
}

SCRIPTS=$(git rev-parse --show-toplevel)/scripts
# shellcheck source=../scripts/common.sh
. "$SCRIPTS"/common.sh

certs_path=./docker/certificates
export CAROOT="$certs_path"
ca_key="$certs_path"/rootCA-key.pem
ca_crt="$certs_path"/rootCA.pem

run_command rm -rf "$certs_path"
run_command mkdir -p "$certs_path"

declare -A servers=(
  ['portainer']='{"CN": "portainer", "hosts": ["portainer", "localhost", "portainer.docker.localhost"]}'
  ['helm']='{"CN": "helm", "hosts": ["helm", "helm.docker.localhost", "host.minikube.internal", "host.kind.internal", "localhost"], "client": true}'
  ['registry']='{"CN": "registry", "hosts": ["registry", "host.minikube.internal", "host.kind.internal", "localhost"], "client": true}'
  ['traefik']='{"CN": "traefik", "hosts": ["traefik", "traefik.docker.localhost"]}'
  ['tools']='{"CN": "local tools", "hosts": ["whoami", "whoami.docker.localhost"]}'
)
for server in helm "${!servers[@]}"; do
  server_key="$certs_path"/${server}-server.key
  server_crt="$certs_path"/${server}-server.crt
  mkcert -key-file "$server_key" -cert-file "$server_crt" $(echo "${servers[$server]}" | jq -r '.hosts[]' | tr '\n' ' ') 2>/dev/null

  log_step "checking certificate..."
  run_command openssl x509 -in "$server_crt" -text -noout >"$server_crt".txt
  run_command openssl verify -CAfile "$ca_crt" "$server_crt" || exit_error "Unable to verify $server_crt"
  run_command openssl x509 -in "$server_crt" -text -noout >"$server_crt".txt

  if [ "$(echo "${servers[$server]}" | jq '.client')" = 'true' ]; then
    client_tls_key="$certs_path"/${server}-client_tls.key
    client_tls_crt="$certs_path"/${server}-client_tls.crt

    # Client TLS certificate
    log_step "creating client certificate..."
    mkcert -client -key-file "$client_tls_key" -cert-file "$client_tls_crt" $(echo "${servers[$server]}" | jq -r '.hosts[]' | tr '\n' ' ') 2>/dev/null
    # check
    log_step "checking client certificate..."
    run_command openssl x509 -in "$client_tls_crt" -text -noout >"$client_tls_crt".txt
    run_command openssl verify -CAfile "$ca_crt" "$client_tls_crt" || exit_error "Unable to verify $client_tls_crt"
  fi
done

mv "$ca_key" "$certs_path"/ca.key
mv "$ca_crt" "$certs_path"/ca.crt

exit 0
