#! /bin/bash

cd "$(dirname "$(readlink -f "$0")")/.." || {
  echo "Unable to go to parent parent folder of $0" >&2
  exit 1
}

exit_error() {
  echo "$1" >&2
  exit 1
}

ROOT_FOLDER="$(pwd)"

declare -A project_handlers_packages=(
  ['dkd']="fastapi uvicorn pyyaml pyjwt passlib bcrypt python-jose pytz python-multipart"
)

for project in "${!project_handlers_packages[@]}"; do
  cd "$ROOT_FOLDER" || exit_error "Unable to go to secret handler root folder"

  [ -d ./"$project" ] || poetry new "$project"
  cd "$project" || exit_error "Unable to go to '$project' folder"

  poetry config --local virtualenvs.create true
  poetry config --local virtualenvs.in-project true

  # shellcheck disable=SC2086
  poetry add ${project_handlers_packages["$project"]}
  poetry add --group dev toml

  # set tool.poetry.scripts.<secret handler> = <secret handler>.main:main in pyproject.toml
  # set tool.poetry.authors = $USER in pyproject.toml
  cat <<EOF | tr -d '\n' | xargs -0 -I {} poetry run python -c {}
import toml;
import os;
data = toml.load("pyproject.toml");

data.setdefault("tool", {}).setdefault("poetry", {})["authors"] = ['author'];
data.setdefault("tool", {}).setdefault("poetry", {}).setdefault("scripts", {})["$project"] = "$(echo "$project" | tr '-' '_').main:main";

toml.dump(data, open("pyproject.toml", "w"));
EOF

  poetry install

done
