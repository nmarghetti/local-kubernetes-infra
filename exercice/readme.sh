#! /bin/sh

cd "$(dirname "$(readlink -f "$0")")" || {
  echo "Unable to go to parent folder of $0" >&2
  exit 1
}
cd ..

for file in exercice/*.md; do
  if [ -f "$file" ]; then
    filename=$(basename "$file")
    dirname=$(dirname "$file")
    number=$(echo "$filename" | sed -re 's#^[0-9]+_(.*).md$#\1#')
    echo "- [$number]($dirname/$filename)"
  fi
done
