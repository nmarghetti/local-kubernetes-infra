#! /bin/sh

# https://github.com/Skarlso/crd-to-sample-yaml

# kubectl get crd

exit_error() {
  echo "$@" >&2
  exit 1
}

echo_error() {
  echo "$@" >&2
}

echo_error "Ensuring to have cty"
[ ! "$(docker container inspect -f json go | jq .[0].Id)" = 'null' ] || docker run -d -ti --name go golang
[ "$(docker container inspect -f json go | jq .[0].State.Running)" = 'true' ] || docker container start go >/dev/null
[ "$(docker container inspect -f json go | jq .[0].State.Running)" = 'true' ] || exit_error 'Unable to start go container'
find /usr/local/share/ca-certificates -maxdepth 2 -type f -name "*.crt" | while IFS= read -r cert; do
  docker cp "$cert" go:/usr/local/share/ca-certificates/"$(basename "$cert")"
done
docker exec -ti go update-ca-certificates -f

docker exec -ti go cty -h >/dev/null || docker exec -ti go bash -c 'cd && rm -rf crd-to-sample-yaml && git clone https://github.com/Skarlso/crd-to-sample-yaml.git && cd crd-to-sample-yaml && make build && cp -f ./cty /usr/local/bin/ && cd .. && rm -rf crd-to-sample-yaml'
docker exec -ti go cty -h >/dev/null || exit_error 'Unable to install cty'

tmpfile=$(mktemp)
trap 'rm -f -- '"$tmpfile" INT TERM HUP EXIT

crds=$1
[ -z "$crds" ] && crds=$(kubectl get crd | tail +2 | cut -d' ' -f1)
for crd in $crds; do
  [ -f ./crd/"$crd".yaml ] && continue

  echo_error "Retrieving crd $1"
  kubectl get crd "$crd" -o yaml >"$tmpfile"
  [ -s "$tmpfile" ] || exit_error "Unable to get crd $crd"

  docker cp "$tmpfile" go:/tmp/crd.yaml
  echo_error "Running cty to generate the sample ./crd/$crd.yaml"
  docker exec -ti go cty generate -c /tmp/crd.yaml -s >./crd/"$crd".yaml
  [ -s ./crd/"$crd".yaml ] || exit_error "Unable to generate sample for crd $crd"
done
