#! /usr/bin/env python3

import boto3
from botocore.exceptions import ClientError, NoCredentialsError, PartialCredentialsError

from secret_handler.secret_manager import SecretManager


class AwsSecretManager(SecretManager):
    def __init__(self, region_name):
        self.region_name = region_name
        try:
            self.client = boto3.client("secretsmanager", region_name=self.region_name)
        except (NoCredentialsError, PartialCredentialsError) as e:
            print(f"Error: {e}")
            raise PermissionError(
                "You are not logged in, you probably need to authenticate: aws configure"
            )
        if not self.has_access_to_secret_manager():
            raise PermissionError(
                f"You don't have access to AWS Secrets Manager in region {region_name}"
            )

    def has_access_to_secret_manager(self):
        try:
            self.client.list_secrets()
            return True
        except ClientError as e:
            if e.response["Error"]["Code"] == "AccessDeniedException":
                return False
            raise e

    def secret_exists(self, secret_id):
        try:
            self.client.describe_secret(SecretId=secret_id)
            return True
        except ClientError as e:
            if e.response["Error"]["Code"] == "ResourceNotFoundException":
                return False
            raise e

    def secret_version_exists(self, secret_id, version):
        try:
            self.client.get_secret_value(SecretId=secret_id, VersionId=version)
            return True
        except ClientError as e:
            if e.response["Error"]["Code"] == "ResourceNotFoundException":
                return False
            raise e

    def create_secret(self, secret_id, secret_value):
        try:
            self.client.create_secret(Name=secret_id, SecretString=secret_value)
            print(f"Secret {secret_id} created successfully.")
        except ClientError as e:
            print(f"Error: {e}")

    def access_secret(self, secret_id, version=None):
        try:
            response = (
                self.client.get_secret_value(SecretId=secret_id)
                if version is None or version == "latest"
                else self.client.get_secret_value(SecretId=secret_id, VersionId=version)
            )
            return response["SecretString"]
        except ClientError as e:
            if e.response["Error"]["Code"] == "ResourceNotFoundException":
                raise ValueError(
                    f"Secret '{secret_id}' version '{version}' does not exist"
                )
            elif e.response["Error"]["Code"] == "AccessDeniedException":
                raise PermissionError(f"Access denied to secret '{secret_id}'")
            else:
                raise e

    def update_secret(self, secret_id, secret_value):
        if not self.secret_exists(secret_id):
            raise ValueError(f"Secret '{secret_id}' does not exist")
        try:
            self.client.update_secret(SecretId=secret_id, SecretString=secret_value)
            print(f"Secret {secret_id} updated successfully.")
        except ClientError as e:
            print(f"Error: {e}")

    def update_secret_from_content(self, secret_id, content):
        if not self.secret_exists(secret_id):
            return self.create_secret(secret_id, content)
        else:
            return self.update_secret(secret_id, content)

    def update_secret_from_file(self, secret_id, file_path):
        content = None
        with open(file_path, "r", encoding="utf8") as file:
            content = file.read()
        if not content:
            print(f"Unable to retrieve content of {file_path}")
            return None
        self.update_secret_from_content(secret_id, content)

    def delete_secret(self, secret_id):
        self.client.delete_secret(
            request={"name": self.client.secret_path(self.project_id, secret_id)}
        )

    def list_versions(self, secret_id):
        if not self.secret_exists(secret_id):
            raise ValueError(f"Secret '{secret_id}' does not exist")
        try:
            response = self.client.list_secret_version_ids(SecretId=secret_id)
            versions = response.get("Versions", [])
            print(f"Version list of secret {secret_id}:")
            for version in versions:
                version_id = version.get("VersionId")
                created_date = version.get("CreatedDate")
                print(f"  - VersionId: {version_id}, CreatedDate: {created_date}")
        except ClientError as e:
            print(f"Error: {e}")

    def delete_version(self, secret_id, version_id):
        if not self.secret_version_exists(secret_id, version_id):
            raise ValueError(
                f"Version '{version_id}' of secret '{secret_id}' does not exist"
            )
        try:
            self.client.update_secret_version_stage(
                SecretId=secret_id,
                VersionStage="AWSPREVIOUS",
                RemoveFromVersionId=version_id,
            )
            print(
                f"Version {version_id} of secret {secret_id} marked as deprecated successfully."
            )
        except ClientError as e:
            print(f"Error: {e}")

    def list_secrets(self, secret_names: list):
        try:
            response = self.client.list_secrets(
                Filters=[
                    {"Key": "name", "Values": secret_names},
                ],
            )
            secrets = response.get("SecretList", [])
            for secret in secrets:
                print(f"Name: {secret['Name']}, ARN: {secret['ARN']}")
        except ClientError as e:
            print(f"Error: {e}")
