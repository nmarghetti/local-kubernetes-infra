#! /bin/bash

cd "$(dirname "$(readlink -f "$0")")/.." || {
  echo "Unable to go to parent parent folder of $0" >&2
  exit 1
}

usage() {
  cat <<EOM
Usage: $0 [options]

Options:
  -a, --app <app>                     : app name of the secret to check (default: $default_app)
  -c, --config <config path or name>  : manifest path or name of the secrets config (default: $default_config)
  -k, --cluster <cluster>             : kubernetes context to use among kind, minikube, test, uat, prod (default: $default_cluster)
  -n, --namespace <namespace>         : namespace of the secret to check (default: $default_namespace)
  -d, --debug                         : debug mode (default)
  -g, --print                         : print go script only
  -s, --store <store path or name>    : manifest path or name of the secrets store (default: $default_store)
  -p, --prefix <prefix>               : prefix for the secret name (default: $default_prefix)
  -h                                  : display this help

Example:
  $0 --app $default_app --cluster $default_cluster --namespace $default_namespace --store $default_store --config $default_config
  $0 --store k8s/flux-playground/external-secrets/vault/fake-cluster-secret-store-config-templated/fake-config-templated.yaml --config k8s/flux-playground/external-secrets/application-core/fake-secrets/fake-secret-config-templated/config.yaml
EOM
}

default_namespace='fake-secrets-config-templated'
default_app='api'
default_config='secrets-config'
default_cluster='minikube'
default_store='fake-config-templated'
default_prefix='external-secrets-'

exit_error() {
  printf "\033[0;31m%s\033[0m\n" "$*" >&2
  exit 1
}

namespace=$default_namespace
app=$default_app
config=$default_config
cluster=$default_cluster
kube_context='kind-kind'
store=$default_store
prefix=$default_prefix
print_only=0

# reset getopts - check https://man.cx/getopts(1)
OPTIND=1
while getopts "ha:c:dgk:n:p:s:-:" opt; do
  case "$opt" in
    a) app="$OPTARG" ;;
    n) namespace="$OPTARG" ;;
    c) config="$OPTARG" ;;
    k) cluster="$OPTARG" ;;
    g) print_only=1 ;;
    p) prefix="$OPTARG" ;;
    s) store="$OPTARG" ;;
    d)
      export PS4=$'+ \t\t''\e[33m\s@\v ${BASH_SOURCE:-}#\e[35m${LINENO} \e[34m${FUNCNAME[0]:+${FUNCNAME[0]}() }''\e[36m\t\e[0m\n'
      set -eoxu pipefail
      ;;
    h)
      usage
      exit 0
      ;;
    -)
      case "$OPTARG" in
        debug)
          export PS4=$'+ \t\t''\e[33m\s@\v ${BASH_SOURCE:-}#\e[35m${LINENO} \e[34m${FUNCNAME[0]:+${FUNCNAME[0]}() }''\e[36m\t\e[0m\n'
          set -eoxu pipefail
          ;;
        app)
          app="${!OPTIND}"
          OPTIND=$((OPTIND + 1))
          ;;
        namespace)
          namespace="${!OPTIND}"
          OPTIND=$((OPTIND + 1))
          ;;
        cluster)
          cluster="${!OPTIND}"
          OPTIND=$((OPTIND + 1))
          ;;
        config)
          config="${!OPTIND}"
          OPTIND=$((OPTIND + 1))
          ;;
        prefix)
          prefix="${!OPTIND}"
          OPTIND=$((OPTIND + 1))
          ;;
        store)
          store="${!OPTIND}"
          OPTIND=$((OPTIND + 1))
          ;;
        print) print_only=1 ;;
        *)
          echo "Unknow option $OPTARG"
          usage
          exit 1
          ;;
      esac
      ;;
    \? | *)
      usage
      exit 1
      ;;
  esac
done
shift $((OPTIND - 1))
[ $# -ne 0 ] && {
  echo "Error: No argument accepted." >&2
  usage
  exit 1
}
case "$cluster" in
  kind) kube_context='kind-kind' ;;
  minikube) kube_context='minikube' ;;
  *)
    echo "Unknown cluster $cluster" >&2
    usage
    exit 1
    ;;
esac

mkdir -p tmp
# file=$(mktemp)
# tmp_file=$(mktemp)
# tmp_templ_file=$(mktemp)
# tmp_json_file=$(mktemp)
# trap 'rm -f -- "$file" "$tmp_file" "$tmp_templ_file" "$tmp_json_file"' INT TERM HUP EXIT
file='tmp/file.go'
tmp_file='tmp/tmp_file'
tmp_templ_file='tmp/tmp_templ_file.tpl'
tmp_json_file='tmp/tmp_json_file.json'

kubectl config use-context "$kube_context"

generate_templ() {
  if [ -f "$config" ]; then
    yq -o json <"$config" | jq >"$tmp_file"
  else
    kubectl get -n "$namespace" configmaps "$config" -o json >"$tmp_file" || exit_error "Unable to get configmap '$config' from namespace '$namespace'"
  fi
  jq -r '.data."'"$app"'"' <"$tmp_file"
}
generate_templ >"$tmp_templ_file"
[ "$(wc -l <"$tmp_templ_file")" -gt 1 ] || exit_error "Unable to get data for app '$app' in configmap '$config'"

retrieve_gcp_store() {
  printf '{ "spec": { "provider": { "fake": { "data": ['
  local first=1
  for key in $(grep "Context := dict" "$tmp_templ_file" | sed -re 's#^[^\$]+\$(.+)Context := dict.*$#\1#'); do
    [ $first -eq 0 ] && printf ',\n'
    [ $first -eq 1 ] && first=0
    printf '{ "key": "%s", "value": ' "$key"
    gcloud secrets versions access latest --secret="${prefix}${key}"
    printf '}'
  done
  printf ']}}}}'
}

generate_jsondata() {
  printf "{"
  local first=1
  if [ -f "$store" ]; then
    yq -o json <"$store" | jq >"$tmp_file"
  else
    if ! kubectl get ClusterSecretStore "$store" -o json >"$tmp_file"; then
      exit_error "Unable to get ClusterSecretStore '$store'"
    fi
  fi
  if [ "$(jq -r '.spec.provider.fake.data | length' <"$tmp_file")" = "0" ]; then
    retrieve_gcp_store >"$tmp_file"
  fi
  for key in $(jq -r '.spec.provider.fake.data[].key' <"$tmp_file"); do
    [ $first -eq 0 ] && printf ","
    printf '"%s": ' "$(echo "$key" | sed -re 's/'"$prefix"'//')"
    jq -r ".spec.provider.fake.data[] | select(.key == \"$key\") | .value" <"$tmp_file"
    first=0
  done
  printf "}"
}
if ! generate_jsondata >"$file"; then
  exit 1
fi
jq <"$file" >"$tmp_json_file"

# gcloud secrets versions access latest --secret=external-secrets-discover

cat <<EOM >"$file"
package main

import (
	"encoding/json"
	"errors"
	"text/template"
	"os"
	"strings"
)

func main() {
	t := template.Must(template.New("DiscoverSecrets").Funcs(template.FuncMap{
		"dict": func(values ...interface{}) (map[string]interface{}, error) {
			if len(values)%2 != 0 {
				return nil, errors.New("invalid dict call")
			}
			dict := make(map[string]interface{}, len(values)/2)
			for i := 0; i < len(values); i += 2 {
				key, ok := values[i].(string)
				if !ok {
					return nil, errors.New("dict keys must be strings")
				}
				dict[key] = values[i+1]
			}
			return dict, nil
		},
		"split": func(s string, d string) []string {
			return strings.Split(d, s)
		},
		"replace": func(old, new, s string) string {
			return strings.Replace(s, old, new, -1)
		},
		"fromJson": func(input interface{}) interface{} {
			return input
		},
	}).Parse(templ))

	m := map[string]interface{}{}
	if err := json.Unmarshal([]byte(jsondata), &m); err != nil {
		panic(err)
	}

	if err := t.Execute(os.Stdout, m); err != nil {
		panic(err)
	}
}

const templ = \`
$(cat "$tmp_templ_file")
\`

const jsondata = \`
$(cat "$tmp_json_file")
\`
EOM

if [ $print_only -eq 1 ]; then
  cat "$file"
  exit 0
fi

[ ! "$(docker container inspect -f json go | jq .[0].Id)" = 'null' ] || docker run -d -ti --name go golang
[ "$(docker container inspect -f json go | jq .[0].State.Running)" = 'true' ] || docker container start go >/dev/null
[ "$(docker container inspect -f json go | jq .[0].State.Running)" = 'true' ] || exit_error 'Unable to start go container'

docker cp "$file" go:/root/check_external_secret.go || exit_error 'Unable to copy file to go container'
cat <<EOM

Run the following command if you want to see the go script executed (or connect to the container):
docker exec -ti go cat /root/check_external_secret.go

EOM
docker exec -ti go go run /root/check_external_secret.go || exit_error 'Go script failed'
