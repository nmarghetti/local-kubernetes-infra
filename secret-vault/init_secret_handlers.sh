#! /bin/bash

cd "$(dirname "$(readlink -f "$0")")" || {
  echo "Unable to go to parent folder of $0" >&2
  exit 1
}

exit_error() {
  echo "$1" >&2
  exit 1
}

ROOT_SECRET_HANDLER_FOLDER="$(pwd)"

gcp_secret_handler='google-cloud-secret-manager google_crc32c'
aws_secret_handler='boto3'

declare -A secret_handlers_packages=(
  # ['gcp-secret-handler']="google-cloud-secret-manager google_crc32c pyyaml"
  # ['aws-secret-handler']="boto3 pyyaml"
  ['secret-handler']="$gcp_secret_handler $aws_secret_handler pyyaml"
)

for secret_handler in "${!secret_handlers_packages[@]}"; do
  cd "$ROOT_SECRET_HANDLER_FOLDER" || exit_error "Unable to go to secret handler root folder"

  [ -d ./"$secret_handler" ] || poetry new "$secret_handler"
  cd "$secret_handler" || exit_error "Unable to go to '$secret_handler' folder"

  poetry config --local virtualenvs.create true
  poetry config --local virtualenvs.in-project true

  # shellcheck disable=SC2086
  poetry add ${secret_handlers_packages["$secret_handler"]}
  poetry add --group dev toml

  # set tool.poetry.scripts.<secret handler> = <secret handler>.main:main in pyproject.toml
  # set tool.poetry.authors = $USER in pyproject.toml
  cat <<EOF | tr -d '\n' | xargs -0 -I {} poetry run python -c {}
import toml;
import os;
data = toml.load("pyproject.toml");

data.setdefault("tool", {}).setdefault("poetry", {})["authors"] = ['author'];
data.setdefault("tool", {}).setdefault("poetry", {}).setdefault("scripts", {})["$secret_handler"] = "$(echo "$secret_handler" | tr '-' '_').main:main";

toml.dump(data, open("pyproject.toml", "w"));
EOF

  poetry install

done
