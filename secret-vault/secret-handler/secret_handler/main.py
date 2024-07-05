#! /usr/bin/env python3

import os
import argparse
import json
import subprocess
import yaml

from typing import List

from secret_handler.aws_secret_manager import AwsSecretManager
from secret_handler.gcp_secret_manager import GcpSecretManager


def get_secret_manager(args):
    if args.provider == "aws":
        return AwsSecretManager(args.aws_region)
    elif args.provider == "gcp":
        return GcpSecretManager(args.gcp_project)
    else:
        raise ValueError(f"Provider {args.provider} not supported")


def build_secret_id(secret, args):
    return f"{args.secret_prefix}{args.project}{args.secret_suffix}-{secret}"


def build_secret_path(args):
    secret_path = f"{args.secret_path.replace('{provider}', args.provider)}/{args.project}{args.secret_suffix}"
    if args.provider == "aws":
        return f"{secret_path}/{args.aws_region}"
    elif args.provider == "gcp":
        return f"{secret_path}/{args.gcp_project}"
    else:
        raise ValueError(f"Provider {args.provider} not supported")


def build_fake_store_path(args):
    return f"{args.secret_path.replace('{provider}', args.provider)}/fake-store"


def build_fake_store_filename(args):
    return f"{args.project}{args.secret_suffix}.yaml"


def import_secrets(args):
    secret_manager = get_secret_manager(args)
    secret_path = build_secret_path(args)
    os.makedirs(build_secret_path(args), exist_ok=True)
    for secret in args.secrets:
        secret_id = build_secret_id(secret, args)
        if secret_manager.secret_exists(secret_id):
            secret_content = secret_manager.access_secret(secret_id)
            secret_extension = "yaml" if secret in args.yaml_secrets else "json"
            secret_file = f"{secret_path}/{secret}.{secret_extension}"
            if secret in args.yaml_secrets:
                secret_content = yaml.dump(
                    json.loads(secret_content),
                    indent=2,
                    default_flow_style=False,
                    default_style="|",
                )
            with open(secret_file, "w", encoding="utf8") as file:
                file.write(secret_content)
            print(f"Importing secret {secret_id} into {secret_file}")
        else:
            print(f"Secret {secret_id} not found in {args.project}")


def create_secrets(args):
    secret_manager = get_secret_manager(args)
    for secret in args.secrets:
        secret_id = build_secret_id(secret, args)
        if secret_manager.secret_exists(secret_id):
            raise ValueError(f"Secret already exists: '{secret_id}'")
        secret_manager.create_secret(secret_id, "{}")


def export_secrets(args):
    secret_manager = get_secret_manager(args)
    secret_path = build_secret_path(args)
    if not os.path.exists(secret_path):
        raise FileNotFoundError(f"Folder {secret_path} does not exist")
    for secret in args.secrets:
        secret_id = build_secret_id(secret, args)
        secret_extension = "yaml" if secret in args.yaml_secrets else "json"
        secret_file = f"{secret_path}/{secret}.{secret_extension}"
        if not os.path.exists(secret_file):
            raise FileNotFoundError(f"File {secret_file} does not exist")
        secret_content = None
        with open(secret_file, "r", encoding="utf8") as file:
            if secret in args.yaml_secrets:
                yaml_object = yaml.safe_load(file)
                secret_content = json.dumps(yaml_object)
            else:
                secret_content = file.read()
        if not secret_content:
            raise ValueError(f"Unable to retrieve content of {secret_file}")
        secret_manager.update_secret_from_content(secret_id, secret_content)


def fake_store(args):
    secret_path = build_secret_path(args)
    fake_store_path = build_fake_store_path(args)
    if not os.path.exists(build_secret_path(args)):
        raise FileNotFoundError(f"Folder {secret_path} does not exist")
    os.makedirs(f"{fake_store_path}", exist_ok=True)
    secrets = []
    for secret in args.secrets:
        secret_extension = "yaml" if secret in args.yaml_secrets else "json"
        secret_file = f"{secret_path}/{secret}.{secret_extension}"
        if not os.path.exists(secret_file):
            raise FileNotFoundError(f"File {secret_file} does not exist")
        secret_content = None
        with open(secret_file, "r", encoding="utf8") as file:
            if secret in args.yaml_secrets:
                yaml_object = yaml.safe_load(file)
                secret_content = json.dumps(yaml_object, indent=2)
            else:
                secret_content = file.read()
        if not secret_content:
            raise ValueError(f"Unable to retrieve content of {secret_file}")
        secrets.append({"key": secret, "value": secret_content})
    with open(
        f"{fake_store_path}/{build_fake_store_filename(args)}", "w", encoding="utf8"
    ) as file:
        file.write(
            yaml.dump(
                {
                    "apiVersion": "external-secrets.io/v1beta1",
                    "kind": "ClusterSecretStore",
                    "metadata": {"name": "fake-store"},
                    "spec": {"provider": {"fake": {"data": secrets}}},
                },
                indent=2,
                default_flow_style=False,
                default_style="|",
            )
        )


def list_secrets(args):
    secret_manager = get_secret_manager(args)
    for secret in args.secrets:
        secret_id = build_secret_id(secret, args)
        secret_manager.list_versions(secret_id)


def details_secrets(args):
    secret_manager = get_secret_manager(args)
    secret_manager.list_secrets(
        list(
            map(
                lambda x: build_secret_id(x, args),
                args.secrets,
            )
        )
    )


def delete_secret_version(args):
    secret_manager = get_secret_manager(args)
    secret_manager.delete_version(build_secret_id(args.secret_name, args), args.version)


def diff_secrets(args):
    secret_path = build_secret_path(args)
    secret_manager = get_secret_manager(args)
    version = args.version
    compare_version = args.compare_version
    for secret in args.secrets:
        print(
            f"Comparing secret {secret} version {version} with version {compare_version}"
        )
        secret_id = build_secret_id(secret, args)
        if not secret_manager.secret_exists(secret_id):
            raise ValueError(f"Secret '{secret_id}' does not exist")
        secret_content = secret_manager.access_secret(secret_id, version)
        secret_extension = "yaml" if secret in args.yaml_secrets else "json"
        compare_secret_file = f"{secret_path}/{secret}.{version}.{secret_extension}"
        if secret in args.yaml_secrets:
            secret_content = yaml.dump(
                json.loads(secret_content),
                indent=2,
                default_flow_style=False,
                default_style="|",
            )
        with open(compare_secret_file, "w", encoding="utf8") as file:
            file.write(secret_content)

        secret_file = f"{secret_path}/{secret}.{secret_extension}"
        if compare_version != "local":
            secret_file = f"{secret_path}/{secret}.{compare_version}.{secret_extension}"
            secret_content = secret_manager.access_secret(secret_id, compare_version)
            if secret in args.yaml_secrets:
                secret_content = yaml.dump(
                    json.loads(secret_content),
                    indent=2,
                    default_flow_style=False,
                    default_style="|",
                )
            with open(secret_file, "w", encoding="utf8") as file:
                file.write(secret_content)

        print(f"Diff between {compare_secret_file} and {secret_file}")
        result = subprocess.run(
            f"diff --color=always -U 4 {compare_secret_file} {secret_file}",
            shell=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        print(result.stdout)


def add_common_args(parser):
    parser.add_argument(
        "--secrets",
        type=str,
        nargs="+",
        default=["application", "cluster", "external"],
        help="List of secrets to handle (default=[application,cluster,external])",
    )
    parser.add_argument(
        "--yaml-secrets",
        type=str,
        nargs="+",
        default=["cluster"],
        help="List of secrets to handle in yaml in local for better reading (default=[cluster])",
    )


def main() -> None:
    os.chdir(os.path.dirname(os.path.realpath(__file__)))

    # create the top-level parser
    parser = argparse.ArgumentParser(
        prog="aws-secret-handler",
        description="""Tool to create/import/export/list/diff/delete secrets from/to AWS/GCP Secret Manager and generate fake store manifest for testing""",
        epilog="""
Examples:
  - secret-handler --project=project --secret-suffix=-test aws --help
  - secret-handler --project=project --secret-suffix=-test gcp --help
    """,
        formatter_class=argparse.RawTextHelpFormatter,
    )
    parser.add_argument(
        "--secret-path",
        type=str,
        default="../../.secrets/{provider}",
        help="path where to import/export secrets (default=../../.secrets/{provider})",
    )
    parser.add_argument(
        "--secret-prefix",
        type=str,
        default="external-secrets-",
        help="Secret prefix to use in the secret manager (default=external-secrets-)",
    )
    parser.add_argument(
        "--project",
        type=str,
        required=True,
        default="project",
        help="Project name, which will be used to build the name of the secret (default=project)",
    )
    parser.add_argument(
        "--secret-suffix",
        type=str,
        default="-test",
        help="Secret suffix to use in the secret manager (default=-test)",
    )

    provider_subparsers = parser.add_subparsers(title="provider", help="provider help")

    # AWS provider
    aws_provider_parser = provider_subparsers.add_parser(
        "aws",
        description="Handling secret from AWS",
        help="Amazon AWS Secret Manager helper",
        epilog="""
Examples:
  - secret-handler aws --region eu-west-1 create --secrets application cluster external
  - secret-handler aws --region eu-west-1 import --secrets application cluster external
  - secret-handler aws --region eu-west-1 export --secrets application cluster external
  - secret-handler aws --region eu-west-1 fake --secrets application cluster external
  - secret-handler aws --region eu-west-1 list --secrets application cluster external
  - secret-handler aws --region eu-west-1 details --secrets application cluster external
  - secret-handler aws --region eu-west-1 delete --secret-name external --version 84e8c4e5-27c7-4nov-z9f5-50c398fe4911
  - secret-handler aws --region eu-west-1 diff --secrets external
    """,
        formatter_class=argparse.RawTextHelpFormatter,
    )
    aws_provider_parser.set_defaults(provider="aws")
    aws_provider_parser.add_argument(
        "--aws-region",
        type=str,
        required=True,
        default=None,
        help="AWS region where the secrets are stored",
    )

    # GCP provider
    gcp_provider_parser = provider_subparsers.add_parser(
        "gcp",
        description="Handling secret from GCP",
        help="Google GCP Secret Manager helper",
        epilog="""
Examples:
  - secret-handler gcp --gcp-project project create --secrets application cluster external
  - secret-handler gcp --gcp-project project import --secrets application cluster external
  - secret-handler gcp --gcp-project project export --secrets application cluster external
  - secret-handler gcp --gcp-project project fake --secrets application cluster external
  - secret-handler gcp --gcp-project project list --secrets application cluster external
  - secret-handler gcp --gcp-project project details --secrets application cluster external
  - secret-handler gcp --gcp-project project delete --secret-name external --version 1
  - secret-handler gcp --gcp-project project diff --secrets external
    """,
        formatter_class=argparse.RawTextHelpFormatter,
    )
    gcp_provider_parser.set_defaults(provider="gcp")
    gcp_provider_parser.add_argument(
        "--gcp-project",
        type=str,
        required=True,
        default=None,
        help="GCP project where the secrets are stored",
    )

    for provider in [aws_provider_parser, gcp_provider_parser]:
        subparsers = provider.add_subparsers(
            title="sub-commands", help="sub-command help"
        )

        # Create
        create_parser = subparsers.add_parser(
            "create",
            help="Create new secrets",
            description="Create nes secrets",
            epilog="""
Examples:
  - secret-handler [option,...] <provider> [provider_option,...] create --secrets application cluster external
    """,
            formatter_class=argparse.RawTextHelpFormatter,
        )
        create_parser.set_defaults(func=create_secrets)
        add_common_args(create_parser)

        # Import
        import_parser = subparsers.add_parser(
            "import",
            help="Retrieve secrets from the vault and store them locally",
            description="Retrieve secrets from the vault and store them locally",
            epilog="""
Examples:
  - secret-handler [option,...] <provider> [provider_option,...] import --secrets application cluster external
    """,
            formatter_class=argparse.RawTextHelpFormatter,
        )
        import_parser.set_defaults(func=import_secrets)
        add_common_args(import_parser)

        # Export
        export_parser = subparsers.add_parser(
            "export",
            help="Use the local files and export them to the vault",
            description="Use the local files and export them to the vault",
            epilog="""
Examples:
  - secret-handler [option,...] <provider> [provider_option,...] export --secrets application cluster external
    """,
            formatter_class=argparse.RawTextHelpFormatter,
        )
        export_parser.set_defaults(func=export_secrets)
        add_common_args(export_parser)

        # Fake store
        fake_parser = subparsers.add_parser(
            "fake",
            help="Use the local files and create a fake store with it",
            description="Use the local files and create a fake store with it",
            epilog="""
Examples:
  - secret-handler [option,...] <provider> [provider_option,...] fake --secrets application cluster external
    """,
            formatter_class=argparse.RawTextHelpFormatter,
        )
        fake_parser.set_defaults(func=fake_store)
        add_common_args(fake_parser)

        # List
        list_parser = subparsers.add_parser(
            "list",
            help="List secrets versions from the vault",
            description="List secrets versions from the vault",
            epilog="""
Examples:
  - secret-handler [option,...] <provider> [provider_option,...] list --secrets application cluster external
    """,
            formatter_class=argparse.RawTextHelpFormatter,
        )
        list_parser.set_defaults(func=list_secrets)
        add_common_args(list_parser)

        # Details
        detail_parser = subparsers.add_parser(
            "details",
            help="List secrets with more details",
            description="List secrets with more details",
            epilog="""
Examples:
  - secret-handler [option,...] <provider> [provider_option,...] details --secrets application cluster external
    """,
            formatter_class=argparse.RawTextHelpFormatter,
        )
        detail_parser.set_defaults(func=details_secrets)
        add_common_args(detail_parser)

        # Delete
        delete_parser = subparsers.add_parser(
            "delete",
            help="Delete secret version in the vault",
            description="Delete secret version in the vault",
            epilog="""
Examples:
  - secret-handler [option,...] <provider> [provider_option,...] delete --secret-name application --version <version id>
    """,
            formatter_class=argparse.RawTextHelpFormatter,
        )
        delete_parser.set_defaults(func=delete_secret_version)
        delete_parser.add_argument(
            "--secret-name",
            type=str,
            required=True,
            help="Secret to delete version from amongs cluster,application,external",
        )
        delete_parser.add_argument(
            "--version",
            type=str,
            required=True,
            help="Version to delete",
        )

        # Diff
        diff_parser = subparsers.add_parser(
            "diff",
            description="Show diff secrets between versions",
            epilog="""
Examples:
  - secret-handler [option,...] <provider> [provider_option,...] diff --secrets application cluster external
    """,
            formatter_class=argparse.RawTextHelpFormatter,
        )
        diff_parser.set_defaults(func=diff_secrets)
        add_common_args(diff_parser)
        diff_parser.add_argument(
            "--version",
            type=str,
            default="latest",
            help="Version to select for diff (default=latest)",
        )
        diff_parser.add_argument(
            "--compare-version",
            type=str,
            default="local",
            help="Version to compare to (default=local)",
        )

    args = parser.parse_args()
    # print(args)
    if "func" in args:
        args.func(args)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
