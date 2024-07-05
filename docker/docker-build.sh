#! /bin/sh

exit_error() {
  echo "$@" >&2
  exit 1
}

cd "$(dirname "$(readlink -f "$0")")" || exit_error "Unable to go into script folder"

[ $# -lt 2 ] && exit_error "Usage: docker-build.sh <app name> <app version>"

app_name=$1
app_version=$2

docker build --build-arg APP_NAME="$app_name" --build-arg APP_VERSION="$app_version" -t "localhost:5007/$app_name:$app_version" . || exit_error "Unable to build the image"
docker push "localhost:5007/$app_name:$app_version" || exit_error "Unable to push the image"
