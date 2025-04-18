#! /bin/bash

compute_dnsmasq_access() {
  export DNSMASQ_PORT="${DNSMASQ_PORT:-53}"
  export DNSMASQ_UI_PORT="${DNSMASQ_UI_PORT:-3053}"
  dnsmasq_url="http://localhost:${DNSMASQ_UI_PORT}"
  dnsmasq_curl_args=(
    '-H' "Authorization: Basic $(printf 'admin:dnsmasq' | base64)"
  )
}

setup_dnsmasq() {
  [ -n "$CLUSTER_DOMAIN" ] || return 1

  compute_dnsmasq_access

  # Ensure to remove that broadcast address from the loopback interface
  if ip addr show lo | grep 10.255.255.254; then
    run_command sudo ip addr del 10.255.255.254/32 dev lo
    run_command docker container restart dnsmasq
  fi

  # Activate and configure dnsmasq if available in the system
  log_info "Ensure to have dnsmasq as first dns resolver"
  if ! grep -qE '^nameserver 127.0.0.1' /etc/resolv.conf; then
    [ -f /etc/dnsmasq.resolv.conf ] && run_command sudo cp -f /etc/resolv.conf /etc/dnsmasq.resolv.conf
    owner=$(stat -c "%U:%G" /etc/resolv.conf)
    (
      printf "# Added by %s\n" "$(readlink -f "$0") at $(date)"
      printf "nameserver 127.0.0.1\n"
      cat /etc/resolv.conf
    ) | sudo sponge /etc/resolv.conf
    # Ensure to have the same owner as before
    sudo chown "$owner" /etc/resolv.conf
  fi
  log_info "Ensure to have dnsmasq configuration for ${CLUSTER_DOMAIN} with ${HOST_IP}"
  if sudo service dnsmasq status 2>/dev/null | grep -i active | grep -qi running; then
    if ! grep -qFx "server=/${CLUSTER_DOMAIN}/${HOST_IP}" /etc/dnsmasq.conf; then
      log_info "Updating local dnsmasq configuration /etc/dnsmasq.conf"
      if grep -qE "^server=/${CLUSTER_DOMAIN}/" /etc/dnsmasq.conf; then
        run_command sudo sed -i -re "s#^server=/${CLUSTER_DOMAIN}/.*\$#server=/${CLUSTER_DOMAIN}/${HOST_IP}#" /etc/dnsmasq.conf
      else
        echo "server=/${CLUSTER_DOMAIN}/${HOST_IP}" | sudo tee -a /etc/dnsmasq.conf >/dev/null
      fi
      run_command sudo service dnsmasq restart
    fi
  fi

  # Activate and configure dnsmasq in docker compose
  log_step "Dnsmasq UI configuration is available at http://localhost:${DNSMASQ_UI_PORT}"
  log_info "Updating dnsmasq configuration in docker compose service"
  local cluster_domain
  for cluster_domain in $(echo "minikube $CLUSTER_DOMAIN" | tr ' ' '\n' | uniq); do
    if grep -qE "^server=/${cluster_domain}/" docker-compose/docker/dnsmasq/dnsmasq.conf; then
      run_command sed -i -re "s#^server=/${cluster_domain}/.*\$#server=/${cluster_domain}/${HOST_IP}#" docker-compose/docker/dnsmasq/dnsmasq.conf
    else
      log_command "echo server=/${cluster_domain}/${HOST_IP} >>docker-compose/docker/dnsmasq/dnsmasq.conf"
      echo "server=/${cluster_domain}/${HOST_IP}" >>docker-compose/docker/dnsmasq/dnsmasq.conf
    fi
  done
  local dns_server
  dns_server=$(grep nameserver /etc/resolv.conf | grep -v 127.0.0.1 | head -1 | awk '{ print $2 }')
  # Override dhcp-option
  if grep -qE "^dhcp-option=" docker-compose/docker/dnsmasq/dnsmasq.conf; then
    run_command sed -i -re "s#^dhcp-option=.*\$#dhcp-option=6,$dns_server#" docker-compose/docker/dnsmasq/dnsmasq.conf
  else
    log_command "echo dhcp-option=6,$dns_server >>docker-compose/docker/dnsmasq/dnsmasq.conf"
    echo "dhcp-option=6,$dns_server" >>docker-compose/docker/dnsmasq/dnsmasq.conf
  fi
  # Override default dns
  if grep -qE "^server=[0-9]" docker-compose/docker/dnsmasq/dnsmasq.conf; then
    run_command sed -i -re "s#^server=[0-9].*\$#server=$dns_server#" docker-compose/docker/dnsmasq/dnsmasq.conf
  else
    log_command "echo server=$dns_server >>docker-compose/docker/dnsmasq/dnsmasq.conf"
    echo "server=$dns_server" >>docker-compose/docker/dnsmasq/dnsmasq.conf
  fi
  code=$(run_command curl "${dnsmasq_curl_args[@]}" -sS -o "$tmp_file_output" -w "%{http_code}" "$dnsmasq_url"/save --data-raw "$(printf '{"/etc/dnsmasq.conf": "%s"}' "$(sed -zre "s#\n#\\\\n#g" docker-compose/docker/dnsmasq/dnsmasq.conf)")")
  if [ "$code" -eq 200 ]; then
    # content updated
    printf 'Waiting for dnsmasq to restart...'
    sleep 5
    for i in $(seq 1 10); do
      if timeout 2 bash -c "</dev/tcp/localhost/53" 2>/dev/null; then
        break
      fi
      printf '.'
      sleep 1
    done
    printf '\n'
    timeout 1 bash -c "</dev/tcp/localhost/53" || exit_error "Unable to update dnsmasq configuration"
  elif [ "$code" -eq 400 ] && grep -q 'no change' "$tmp_file_output"; then
    : # no change
  else
    echo "code: $code"
    cat "$tmp_file_output"
    exit_error "Unable to update dnsmasq configuration"
  fi

  log_info "Ensure podinfo is deployed"
  kubectl rollout status -n ingress-nginx deployment ingress-nginx-controller || exit_error "nginx ingress controller is not ready"
  # Delete info namespace if it exists but there is no ingress for podinfo
  if kubectl get namespace info &>/dev/null; then
    if ! kubectl get -n info ingress podinfo-minikube &>/dev/null; then
      kubectl delete namespace info
    fi
  fi
  # shellcheck source=../k8s/podinfo/setup_podinfo.sh
  . "$GIT_ROOT"/k8s/podinfo/setup_podinfo.sh
  install_podinfo_with_kubectl || exit_error "Unable to install podinfo"
  cluster_domain="${CLUSTER_DOMAIN}"
  if [ ! "$CLUSTER_DOMAIN" = "minikube" ]; then
    if ! kubectl api-resources --no-headers --api-group 'traefik.io' | wc -l | grep -qFx 0; then
      kubectl --namespace info create ingress --class nginx --rule "podinfo.$CLUSTER_DOMAIN/*=podinfo:9898" --dry-run=client -o yaml podinfo-domain | kubectl apply -f -
      cat <<EOM | kubectl apply -f -
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  annotations:
    kubernetes.io/ingress.class: traefik
  name: podinfo
  namespace: info
spec:
  entryPoints:
    - web
    - websecure
  routes:
    - kind: Rule
      match: Host($(printf '`podinfo-traefik.%s`' ${CLUSTER_DOMAIN}))
      services:
        - kind: Service
          name: podinfo
          port: 9898
EOM
    else
      cluster_domain="minikube"
      log_warn "Traefik is not available, unable to create ingress to target 'podinfo.${CLUSTER_DOMAIN}' yet. Please rerun when traefik is available."
    fi
  fi

  log_info "Checking resolution of podinfo.${cluster_domain}"
  run_command_hide nslookup podinfo."${cluster_domain}" 127.0.0.1 || exit_error "Unable to resolve podinfo.${cluster_domain}"
  run_command nslookup podinfo."${cluster_domain}" 127.0.0.1 | grep -qiE "^name:.*podinfo.$cluster_domain" || log_error "Unable to resolve podinfo.${cluster_domain}"

  log_step "Podinfo available at http://podinfo.${cluster_domain} and http://podinfo.${cluster_domain}/swagger/index.html only under WSL local network (not under Windows host)"

  return 0
  # log_step "Dkd swagger is available at http://dkd.minikube/dkd/docs"
  # chrome://flags/#allow-insecure-localhost
  # kubectl get -n elastic-system secrets analytics-kb-es-ca -o json | jq '.data."ca.crt" | @base64d' | xargs printf >
}

# If the script is not being sourced, run the setup
(return 0 2>/dev/null) || {
  cd "$(dirname "$(readlink -f "$0")")" || {
    echo "Unable to go to parent folder of $0" >&2
    exit 1
  }

  SCRIPTS=$(git rev-parse --show-toplevel)/scripts
  # shellcheck source=./common.sh
  . "$SCRIPTS"/common.sh
  # shellcheck source=./setup_minikube.sh
  . "$SCRIPTS"/setup_minikube.sh
  # shellcheck source=./setup_kind.sh
  . "$SCRIPTS"/setup_kind.sh
  # shellcheck source=./setup_cluster_access.sh
  . "$SCRIPTS"/setup_cluster_access.sh

  cd "$GIT_ROOT" || exit_error "Unable to go to git root folder"

  tmp_file_output=$(mktemp)
  trap 'rm -f -- $tmp_file_output' INT TERM HUP EXIT

  parse_args "$@"

  compute_cluster_access
  setup_dnsmasq

  exit 0
}
