#! /bin/bash

[ "$USE_INIT_CONTAINER" = "0" ] && exit 0

if [ "$DEBUG_INIT_CONTAINER" = "1" ]; then
  export PS4=$'+ \t\t''\e[33m\s@\v ${BASH_SOURCE:-}#\e[35m${LINENO} \e[34m${FUNCNAME[0]:+${FUNCNAME[0]}() }''\e[36m\t\e[0m\n'
  set -eoxu pipefail
  env | sort
fi

git init &>/dev/null

# shellcheck source=../../../scripts/common.sh
. ./scripts/common.sh
# shellcheck source=../../../scripts/setup_portainer.sh
. ./scripts/setup_portainer.sh

export PORTAINER_PORT="${PORTAINER_PORT:-9400}"
export PORTAINER_DOCKER_HOST=portainer
PORTAINER_DOCKER_PORT=9000
[ "$USE_SSL" = '1' ] && PORTAINER_DOCKER_PORT=9443
export PORTAINER_DOCKER_PORT

tmp_file_output=$(mktemp)
trap 'rm -f -- $tmp_file_output' INT TERM HUP EXIT

setup_portainer
