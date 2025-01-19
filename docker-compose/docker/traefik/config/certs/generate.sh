#! /bin/bash

cd "$(dirname "$(readlink -f "$0")")" || {
  echo "Unable to go to parent folder of $0" >&2
  exit 1
}

SCRIPTS=$(git rev-parse --show-toplevel)/scripts
# shellcheck source=../../../../../scripts/common.sh
. "$SCRIPTS"/common.sh

cluster=$1
if [ -z "$cluster" ]; then
  log_error "No cluster provided (minikube or kind). Usage: $0 <cluster>"
  exit 1
fi

ca_key="$GIT_ROOT/tmp/${cluster}_ca.key"
ca_crt="$GIT_ROOT/tmp/${cluster}_ca.crt"
ca_name="${cluster}CA"
certs_path=.

# If cluster is not even installed yet, generate some certificates with mkcert
if [ ! -f "$ca_key" ]; then
  ca_key="$certs_path"/rootCA-key.pem
  ca_crt="$certs_path"/rootCA.pem
  ca_name=mkcertCA
  CAROOT="$certs_path" mkcert -key-file "$certs_path/traefik-${cluster}-server.key" -cert-file "$certs_path/traefik-${cluster}-server.crt" "localhost"
fi

if [ -f "$certs_path/traefik-${cluster}-server.crt" ] && openssl verify -CAfile "$ca_crt" "$certs_path/traefik-${cluster}-server.crt" &>/dev/null; then
  log_info "Certificate already generated for $cluster"
  exit 0
fi

get_subject() {
  printf "/C=FR/ST=PACA/L=Nice/O=MyCompany/OU=RnD/CN=%s/emailAddress=%s@no-reply.com" "$1" "$1"
}

# openssl verify -CAfile "$ca_crt" "$server_crt"
declare -A servers=(
  ['traefik']='{"CN": "traefik-'"$cluster"'", "hosts": ["traefik", "traefik.docker.localhost", "localhost", "nginx-minikube-k8s.localhost", "nginx-kind-k8s.localhost", "nginx-kind-tls.localhost"]}'
)
for server in "${!servers[@]}"; do
  server_key="$certs_path/${server}-${cluster}-server.key"
  server_csr="$certs_path/${server}-${cluster}-server.csr"
  server_crt="$certs_path/${server}-${cluster}-server.crt"
  server_conf="$certs_path/${server}-${cluster}-server.conf"

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
