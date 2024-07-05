#! /usr/bin/env python3

import os

from google.cloud import secretmanager
from google.api_core.exceptions import NotFound, Forbidden
from google.auth.exceptions import DefaultCredentialsError


class GcpSecretManager:
    def __init__(self, project_id):
        self.project_id = project_id
        try:
            self.client = secretmanager.SecretManagerServiceClient()
        except DefaultCredentialsError as e:
            print(f"Error: {e}")
            raise PermissionError(
                f"You are not logged, you probably need to authenticate: gcloud auth application-default login --project {project_id}"
            )
        if not self.has_access_to_secret_manager():
            raise PermissionError(
                f"You dont have access to Google Secret Manager for project {project_id}"
            )

    def has_access_to_secret_manager(self):
        try:
            parent = f"projects/{self.project_id}"
            self.client.list_secrets(request={"parent": parent})
            return True
        except Forbidden:
            return False

    def secret_exists(self, secret_id):
        try:
            name = f"projects/{self.project_id}/secrets/{secret_id}"
            self.client.get_secret(name=name)
            return True
        except NotFound:
            return False

    def secret_version_exists(self, secret_id, version):
        try:
            name = f"projects/{self.project_id}/secrets/{secret_id}/versions/{version}"
            self.client.get_secret_version(request={"name": name})
            return True
        except NotFound:
            return False

    def create_secret(self, secret_id, secret_value):
        print(f"Creating secret {secret_id}")
        parent = f"projects/{self.project_id}"
        secret = self.client.create_secret(
            request={
                "parent": parent,
                "secret_id": secret_id,
                "secret": {"replication": {"automatic": {}}},
            }
        )
        return self.client.add_secret_version(
            request={
                "parent": secret.name,
                "payload": {"data": secret_value.encode("UTF-8")},
            }
        )

    def access_secret(self, secret_id, version="latest"):
        name = f"projects/{self.project_id}/secrets/{secret_id}/versions/{version}"
        response = self.client.access_secret_version(request={"name": name})
        return response.payload.data.decode("UTF-8")

    def update_secret(self, secret_id, secret_value):
        print(f"Updating secret {secret_id}")
        return self.client.add_secret_version(
            request={
                "parent": self.client.secret_path(self.project_id, secret_id),
                "payload": {"data": secret_value.encode("UTF-8")},
            }
        )

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
        print(f"Version list of secret {secret_id}:", end=" ")
        versions = [
            version
            for version in self.client.list_secret_versions(
                request={"parent": f"projects/{self.project_id}/secrets/{secret_id}"}
            )
            if version.state == 1
        ]
        print(", ".join([os.path.basename(version.name) for version in versions]))

    def delete_version(self, secret_id, version):
        if not self.secret_version_exists(secret_id, version):
            raise ValueError(f"Secret '{secret_id}' version '{version}' does not exist")
        self.client.destroy_secret_version(
            request={
                "name": f"projects/{self.project_id}/secrets/{secret_id}/versions/{version}"
            }
        )

    def list_secrets(self, secret_names: list):
        for secret in secret_names:
            if self.secret_exists(secret):
                print(secret)
