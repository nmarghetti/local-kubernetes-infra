# Secret vault

Initialize secrets handler:

```shell
./secret-vault/init_secret_handlers.sh
```

Run secret handler:

```shell
# Either activate with poetry shell and run it
poetry -C ./secret-vault/secret-handler shell
secret-handler --help
# deactive when done
deactivate

# Either run it through poetry
poetry -C ./secret-vault/secret-handler run secret-handler --help
```

## GCP

```shell
# First authenticate to your GCP project
gcloud auth application-default login --project <project id>

secret-handler --project project gcp --gcp-project <project id> list --secrets cluster external
secret-handler --project project gcp --gcp-project <project id> create --secrets cluster external
secret-handler --project project gcp --gcp-project <project id> initialize --secrets cluster external
secret-handler --project project gcp --gcp-project <project id> details --secrets cluster external
secret-handler --project project gcp --gcp-project <project id> import --secrets cluster external
secret-handler --project project gcp --gcp-project <project id> export --secrets cluster external
secret-handler --project project gcp --gcp-project <project id> diff --secrets cluster external
secret-handler --project project gcp --gcp-project <project id> fake --secrets cluster external
secret-handler --project project gcp --gcp-project <project id> delete --secret-name external --version 1
```

## AWS

```shell
# First configure AWS
aws configure

secret-handler --project project aws --aws-region eu-west-1 list --secrets cluster external
secret-handler --project project aws --aws-region eu-west-1 create --secrets cluster external
secret-handler --project project aws --aws-region eu-west-1 initialize --secrets cluster external
secret-handler --project project aws --aws-region eu-west-1 details --secrets cluster external
secret-handler --project project aws --aws-region eu-west-1 import --secrets cluster external
secret-handler --project project aws --aws-region eu-west-1 export --secrets cluster external
secret-handler --project project aws --aws-region eu-west-1 diff --secrets cluster external
secret-handler --project project aws --aws-region eu-west-1 fake --secrets cluster external
secret-handler --project project aws --aws-region eu-west-1 delete --secret-name external --version 84e8c4e5-27c7-4nov-z9f5-50c398fe4911
```
