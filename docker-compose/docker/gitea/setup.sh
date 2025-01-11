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
# shellcheck source=../../../scripts/setup_gitea.sh
. ./scripts/setup_gitea.sh

export GITEA_PORT="${GITEA_PORT:-3000}"
export GITEA_DOCKER_HOST=gitea
export GITEA_DOCKER_PORT=3000
export GITEA_SET_WEBHOOK=${GITEA_SET_WEBHOOK:-0}

tmp_file_output=$(mktemp)
trap 'rm -f -- $tmp_file_output' INT TERM HUP EXIT

setup_gitea
