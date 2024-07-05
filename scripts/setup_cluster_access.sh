#! /bin/bash

compute_cluster_access() {
  if [ "$use_minikube" -eq 1 ]; then
    compute_minikube_access
  elif [ "$use_kind" -eq 1 ]; then
    compute_kind_access
  else
    log_error "You did not choose if you use minikube or kind (--kind | --minikube)"
  fi
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

  cd "$GIT_ROOT" || exit_error "Unable to go to git root folder"

  parse_args "$@"

  compute_cluster_access

  exit 0
}
