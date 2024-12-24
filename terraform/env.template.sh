#! /bin/sh

# If you user keybase
# export TF_VAR_pgp_key="keybase:$USER"
TF_VAR_pgp_key="$(gpg --export "$USER" | base64)"
export TF_VAR_pgp_key
TF_VAR_aws_account_id="$(aws sts get-caller-identity --query "Account" --output text)"
export TF_VAR_aws_account_id
