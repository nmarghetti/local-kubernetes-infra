#! /usr/bin/env python3

from abc import ABC, abstractmethod


class SecretManager(ABC):
    @abstractmethod
    def create_secret(self, secret_id, secret_value):
        pass

    @abstractmethod
    def access_secret(self, secret_id):
        pass

    @abstractmethod
    def update_secret(self, secret_id, secret_value):
        pass

    @abstractmethod
    def delete_secret(self, secret_id):
        pass

    @abstractmethod
    def list_secrets(self):
        pass

    @abstractmethod
    def list_versions(self, secret_id):
        pass

    @abstractmethod
    def secret_exists(self, secret_id):
        pass

    @abstractmethod
    def secret_version_exists(self, secret_id, version):
        pass
