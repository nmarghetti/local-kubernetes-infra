#! /bin/bash

# https://blog.devolutions.net/2020/07/tutorial-how-to-generate-secure-self-signed-server-and-client-certificates-with-openssl/
# chrome://flags/#allow-insecure-localhost
# https://superuser.com/questions/1428012/cant-verify-an-openssl-certificate-against-a-self-signed-openssl-certificate

cd "$(dirname "$(readlink -f "$0")")" || {
  echo "Unable to go to parent folder of $0" >&2
  exit 1
}

SCRIPTS=$(git rev-parse --show-toplevel)/scripts
# shellcheck source=../scripts/common.sh
. "$SCRIPTS"/common.sh

certs_path=./docker/certificates
run_command rm -rf "$certs_path"
run_command mkdir -p "$certs_path"

get_subject() {
  printf "/C=FR/ST=PACA/L=Nice/O=MyCompany/OU=RnD/CN=%s/emailAddress=%s@no-reply.com" "$1" "$1"
}

ca_key="$certs_path"/ca.key
ca_crt="$certs_path"/ca.crt
ca_name=localca
ca_subject=$(get_subject "$ca_name")

# Certificate Authority
run_command openssl ecparam -name prime256v1 -genkey -noout -out "$ca_key"
run_command openssl req -new -x509 -sha256 -key "$ca_key" -out "$ca_crt" -subj "$ca_subject"
# check
run_command openssl x509 -in "$ca_crt" -text -noout >"$ca_crt".txt
echo

declare -A servers=(
  ['portainer']='{"CN": "portainer", "hosts": ["portainer", "localhost", "portainer.docker.localhost"]}'
  ['helm']='{"CN": "helm", "hosts": ["helm", "helm.docker.localhost", "host.local-cluster.internal", "host.minikube.internal", "host.kind.internal", "localhost"], "client": true}'
  ['registry']='{"CN": "registry", "hosts": ["registry", "host.local-cluster.internal", "host.minikube.internal", "host.kind.internal", "localhost"], "client": true}'
  ['traefik']='{"CN": "traefik", "hosts": ["traefik", "traefik.docker.localhost"]}'
  ['tools']='{"CN": "local tools", "hosts": ["whoami", "whoami.docker.localhost"]}'
)

for server in "${!servers[@]}"; do
  server_key="$certs_path"/${server}-server.key
  server_csr="$certs_path"/${server}-server.csr
  server_crt="$certs_path"/${server}-server.crt
  server_conf="$certs_path"/${server}-server.conf

  cat <<EOF >"$server_conf"
[req]
distinguished_name = req_distinguished_name
req_extensions = req_ext
prompt = no

[req_distinguished_name]
C = FR
ST = PACA
L = Nice
O = MyCompany
OU = RnD
CN = $ca_name
# CN = $server

[req_ext]
subjectAltName = @alt_names

[alt_names]
$(echo "${servers[$server]}" | jq '.hosts | to_entries | map({index: .key, value: .value}) | .[] | "DNS.\(1+.index) = \(.value)"' | xargs printf "%s\n")
EOF

  log_info "Generating certificates for $server"
  # Server certificate
  run_command openssl ecparam -name prime256v1 -genkey -noout -out "$server_key"
  run_command openssl req -new -sha256 -key "$server_key" -out "$server_csr" -subj "$(get_subject "$(echo "${servers[$server]}" | jq '.CN' | xargs printf "%s")")"
  # run_command openssl x509 -req -in "$server_csr" -CA "$ca_crt" -CAkey "$ca_key" -CAcreateserial -out "$server_crt" -days 1000 -sha256 -extfile "$server_conf"
  run_command openssl x509 -req -in "$server_csr" -CA "$ca_crt" -CAkey "$ca_key" -CAcreateserial -out "$server_crt" -days 1000 -sha256 -extfile <(printf "subjectAltName=%s" "$(echo "${servers[$server]}" | jq -r '[.hosts | to_entries | map({index: .key, value: .value}) | .[] | "DNS:\(.value)"] | join(",")')")
  # run_command openssl req -new -sha256 -key "$server_key" -out "$server_csr" -config openssl-server.conf -subj "$(get_subject "$(echo "${servers[$server]}" | jq '.CN' | xargs printf "%s")")"
  # run_command openssl x509 -req -in "$server_csr" -CA "$ca_crt" -CAkey "$ca_key" -CAcreateserial -out "$server_crt" -days 1000 -sha256 -extfile <(printf "subjectAltName=DNS:localhost,DNS:host.minikube.internal")

  # run_command openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$server_key"
  # run_command openssl req -new -key "$server_key" -out "$server_csr" -config "$server_conf"
  # run_command openssl x509 -req -in "$server_csr" -CA "$ca_crt" -CAkey "$ca_key" -out "$server_crt" -days 365 -extfile "$server_conf" -extensions req_ext
  # # run_command openssl x509 -req -in "$server_csr" -signkey "$server_key" -out "$server_crt" -days 365 -extfile "$server_conf" -extensions req_ext
  chmod +r "$server_key"
  # check
  log_step "checking certificate..."
  run_command openssl req -noout -text -verify -in "$server_csr" >"$server_csr".txt || exit_error "Unable to verify $server_csr"
  run_command openssl x509 -in "$server_crt" -text -noout >"$server_crt".txt
  run_command openssl verify -CAfile "$ca_crt" "$server_crt" || exit_error "Unable to verify $server_crt"
  echo

  if [ "$(echo "${servers[$server]}" | jq '.client')" = 'true' ]; then
    client_tls_key="$certs_path"/${server}-client_tls.key
    client_tls_csr="$certs_path"/${server}-client_tls.csr
    client_tls_crt="$certs_path"/${server}-client_tls.crt
    client_cn="local-${server}-client"
    client_email="${client_cn}@no-reply.com"

    # Client TLS certificate
    log_step "creating client certificate..."
    run_command openssl ecparam -name prime256v1 -genkey -noout -out "$client_tls_key"
    run_command openssl req -new -sha256 -key "$client_tls_key" -out "$client_tls_csr" -subj "/C=FR/ST=PACA/L=Nice/O=MyCompany/OU=DEX/CN=${client_cn}/emailAddress=${client_email}"
    run_command openssl x509 -req -in "$client_tls_csr" -CA "$ca_crt" -CAkey "$ca_key" -CAcreateserial -out "$client_tls_crt" -days 1000 -sha256 -extfile "$server_conf"
    # check
    log_step "checking client certificate..."
    run_command openssl req -noout -text -verify -in "$client_tls_csr" >"$client_tls_csr".txt || exit_error "Unable to verify $client_tls_csr"
    run_command openssl x509 -in "$client_tls_crt" -text -noout >"$client_tls_crt".txt
    run_command openssl verify -CAfile "$ca_crt" "$client_tls_crt" || exit_error "Unable to verify $client_tls_crt"
  fi
done

exit 0
