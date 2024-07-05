#! /bin/bash

cd "$(dirname "$(readlink -f "$0")")/.." || {
  echo "Unable to go to parent parent folder of $0" >&2
  exit 1
}

# shellcheck source=./common.sh
. ./scripts/common.sh

usage() {
  cat <<EOM
Usage: $0 [options]

Options:
  -n, --name <name> : name to use for the playground
  -s, --single      : use single level flux
  -m, --multi-level : use multi level flux
  -f, --force       : force the creation, it will remove existing playground
  -h                : display this help
EOM
}

parse_args() {
  name=
  multi_level=0
  force=0
  # reset getopts - check https://man.cx/getopts(1)
  OPTIND=1
  while getopts "hn:fsm-:" opt; do
    case "$opt" in
      n) name="$OPTARG" ;;
      s) multi_level=0 ;;
      m) multi_level=1 ;;
      f) force=1 ;;
      h)
        usage
        exit 0
        ;;
      -)
        case "$OPTARG" in
          name)
            name="${!OPTIND}"
            OPTIND=$((OPTIND + 1))
            ;;
          single) multi_level=0 ;;
          multi-level) multi_level=1 ;;
          force) force=1 ;;
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
  [ -z "$name" ] && exit_error "You must provide a name for the playground"
  return 0
}

parse_args "$@"

[ -e "./k8s/flux-playground/$name" ] && [ $force -eq 0 ] && exit_error "Playground $name already exists"
[ -e "./k8s/flux-playground/$name" ] && [ $force -eq 1 ] && rm -rf "./k8s/flux-playground/$name"

echo "Creating playground $name"
mkdir -p "./k8s/flux-playground/$name"

if [ $multi_level -eq 1 ]; then
  cp -r "./k8s/flux/template"/* "./k8s/flux-playground/$name/"
  grep -rH './k8s/.../' "./k8s/flux-playground/$name" | cut -d':' -f1 | while IFS= read -r file; do
    sed -i -re 's#./k8s/.../#'"./k8s/flux-playground/$name/"'#' "$file"
  done
else
  mkdir -p "./k8s/flux-playground/$name/flux-system"
  cp -r "./k8s/flux/template/flux-system/flux-system"/* "./k8s/flux-playground/$name/flux-system/"
fi
git add "./k8s/flux-playground/$name"
git commit -m "Create flux playground $name"
