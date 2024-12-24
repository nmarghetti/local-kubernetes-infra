# Terraform

## Encryption

### GPG

```shell
# Either create private and public gpg key with prompt
gpg --full-generate-key

# Either automate it
# Generate GPG key if not already done
if ! gpg --list-keys "$(git config user.email)" >/dev/null 2>&1; then
  cat >./tmp/gen-key-script <<EOF
%no-protection
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: $USER
Name-Email: $(git config user.email)
Expire-Date: 0
%commit
EOF
gpg --batch --generate-key ./tmp/gen-key-script
rm -f ./tmp/gen-key-script
```

### Keybase

Keybase will allow to encrypt data within terraform state.
Create an account <https://keybase.io/>.

```shell
# https://keybase.io/docs/the_app/install_linux
# install keybase
curl --remote-name https://prerelease.keybase.io/keybase_amd64.deb &&
  sudo apt install -y ./keybase_amd64.deb &&
  rm -f ./keybase_amd64.deb
```

When done, create a gpg public key on your account and import it:

```shell
# Put you account if different from your username
keybase_account="$USER"

# Import to gpg
curl "https://keybase.io/${keybase_account}/pgp_keys.asc" | gpg --import
# List gpg keys
gpg --list-keys
```

On <https://keybase.io/>, go to `Me` section to see you GPG key, click on `edit` and `Export my private key from Keybase`. Save the content of your private key in a file and import it to gpg.

```shell
gpg --import <your private key file>
# List gpg secret keys
gpg --list-secret-keys
```

## Terraform cli

### Secrets variables

First export some variable that contains some secrets.

```shell
# Copy template and fill it up with proper values per workspace, eg. test:
cp ./terraform/env.template.sh ./terraform/env.test.sh
. ./terraform/env.test.sh
```

### Workspaces

```shell
# List
terraform -chdir=./terraform workspace list
# Create
terraform -chdir=./terraform workspace new <PUT_NAME>
terraform -chdir=./terraform workspace new test
# Select
terraform -chdir=./terraform workspace select test
```

### Apply

```shell
terraform -chdir=./terraform init
# Put the variables files depending on the workspace selected
terraform -chdir=./terraform plan -var-file="terraform.test.tfvars"
# Put the variables files depending on the workspace selected
terraform -chdir=./terraform apply -var-file="terraform.test.tfvars" -auto-approve

# You might need to select only some target as others can depend on it
terraform -chdir=./terraform plan -var-file="terraform.test.tfvars" -target=module.aws.data.aws_iam_users.iam_users -out=../tmp/terraform.plan
terraform -chdir=./terraform apply ../tmp/terraform.plan

# Import existing resources
terraform -chdir=./terraform import -var-file="terraform.test.tfvars" module.aws.module.iam_users[\"project_SecretManager\"].aws_iam_user.this[0] project_SecretManager
terraform -chdir=./terraform import -var-file="terraform.test.tfvars" module.aws.aws_iam_policy.external_secrets[0] arn:aws:iam::${TF_VAR_aws_account_id}:policy/external-secrets-project-test
terraform -chdir=./terraform import -var-file="terraform.test.tfvars" module.aws.aws_iam_role.external_secrets[0] external-secrets-project-test

# Taint deleted resources to recreate them
terraform -chdir=./terraform taint module.aws.module.iam_users[\"project_SecretManager\"].aws_iam_user.this[0]
terraform -chdir=./terraform untaint module.aws.module.iam_users[\"project_SecretManager\"].aws_iam_user.this[0]

# Remove resources from local state
terraform -chdir=./terraform state rm taint module.aws.module.iam_users[\"project_SecretManager\"].aws_iam_user.this[0]
```

### Retrieve secrets

```shell
jq -r '.outputs.users_secret_access.value.project_SecretManager.secret_access_key' < terraform/terraform.tfstate.d/test/terraform.tfstate | gpg --decrypt | xargs echo
# Use temporary file if needed
cat terraform/terraform.tfstate.d/test/terraform.tfstate | jq -r '.outputs.users_secret_access.value.project_SecretManager.secret_access_key' > ./tmp/pgp_message.txt && gpg --decrypt ./tmp/pgp_message.txt | xargs echo
```
