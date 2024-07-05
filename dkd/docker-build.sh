#! /bin/sh

cd "$(dirname "$(readlink -f "$0")")" || {
  echo "Unable to go to parent folder of $0" >&2
  exit 1
}

SCRIPTS=$(git rev-parse --show-toplevel)/scripts
# shellcheck source=../scripts/common.sh
. "$SCRIPTS"/common.sh

docker buildx build -t "localhost:5007/dkd" --output type=docker . || exit_error "Unable to build the image"
docker push "localhost:5007/dkd" || exit_error "Unable to push the image"
