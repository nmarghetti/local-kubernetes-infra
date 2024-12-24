#! /bin/sh

cd "$(dirname "$(readlink -f "$0")")" || {
  echo "Unable to go to parent folder of $0" >&2
  exit 1
}

unset AWS_ACCESS_KEY AWS_SECRET_ACCESS_KEY
envFile="$PWD/aws_secret.env"

[ -f "$envFile" ] || {
  cat <<EOM >&2
File '$envFile' not found.

Please create it with the following command:
touch "$envFile"

Then, add the following content to it:
export AWS_ACCESS_KEY=<your-access-key>
export AWS_SECRET_ACCESS_KEY=<your-secret-access-key>

EOM
  exit 1
}

# shellcheck disable=SC1090
. "$envFile"

if [ -z "$AWS_ACCESS_KEY" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
  echo "AWS_ACCESS_KEY and AWS_SECRET_ACCESS_KEY must be set in '$envFile'" >&2
  exit 1
fi

kubectl get namespace external-secrets >/dev/null 2>&1 || kubectl create namespace external-secrets
kubectl create secret generic awssm-secret -n external-secrets --from-literal=access-key="$AWS_ACCESS_KEY" --from-literal=secret-access-key="$AWS_SECRET_ACCESS_KEY" --dry-run=client -o yaml | kubectl apply -f -
