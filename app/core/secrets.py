import json
from functools import lru_cache

import boto3
from botocore.exceptions import ClientError

from app.core.config import get_settings


@lru_cache
def _secretsmanager_client():
    settings = get_settings()
    session = boto3.session.Session()
    return session.client(service_name="secretsmanager", region_name=settings.aws_region)


@lru_cache
def get_secret(secret_name: str) -> dict[str, str]:
    try:
        response = _secretsmanager_client().get_secret_value(SecretId=secret_name)
    except ClientError as e:
        raise RuntimeError(f"Unable to read secret {secret_name!r} from Secrets Manager") from e
    return json.loads(response["SecretString"])


@lru_cache
def get_crm_api_key() -> str:
    """Returns the CRM API key.

    In-cluster, this is synced by the External Secrets Operator into the
    APP_CRM_API_KEY env var (see k8s/external-secrets/) — no AWS credentials
    needed in the pod. Locally, it falls back to fetching the secret directly
    via boto3, using whatever credentials `aws configure` already set up.
    """
    settings = get_settings()
    if settings.crm_api_key:
        return settings.crm_api_key
    return get_secret(settings.crm_api_key_secret_name)["API_KEY"]
