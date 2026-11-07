"""Credentials read at startup from AWS Secrets Manager; never logged."""

import json


def read_aws_secret(secret_id: str, region: str, field: str) -> str:
    """Read one credential into process memory using the instance/workload role."""
    try:
        import boto3
        from botocore.config import Config

        client = boto3.client(
            "secretsmanager",
            region_name=region,
            config=Config(
                connect_timeout=3,
                read_timeout=5,
                retries={"mode": "standard", "total_max_attempts": 2},
            ),
        )
        try:
            value = json.loads(
                client.get_secret_value(SecretId=secret_id)["SecretString"]
            )
        finally:
            client.close()
        key = value.get(field) if isinstance(value, dict) else None
        if not isinstance(key, str) or not key.strip():
            raise ValueError("Credential is missing")
        return key.strip()
    except Exception:
        # Do not include upstream responses, secret JSON or credential material
        # in startup tracebacks. A failed read must fail closed.
        raise RuntimeError(
            "Requested credential is unavailable in AWS Secrets Manager"
        ) from None
