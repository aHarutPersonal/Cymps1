"""Optional local macOS credential storage; deployments use injected secrets."""

import ctypes
import json
import sys


def read_aws_secret(secret_id: str, region: str, field: str = "OPENLUX_API_KEY") -> str:
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


def read_keychain_secret(service: str, account: str = "cmpys") -> str:
    if sys.platform != "darwin":
        raise RuntimeError(
            "Keychain credentials require macOS; inject OPENLUX_API_KEY instead"
        )
    security = ctypes.CDLL("/System/Library/Frameworks/Security.framework/Security")
    pointer = ctypes.c_void_p
    security.SecKeychainSetUserInteractionAllowed.argtypes = [ctypes.c_bool]
    security.SecKeychainSetUserInteractionAllowed(False)
    security.SecKeychainFindGenericPassword.argtypes = [
        pointer,
        ctypes.c_uint32,
        ctypes.c_char_p,
        ctypes.c_uint32,
        ctypes.c_char_p,
        ctypes.POINTER(ctypes.c_uint32),
        ctypes.POINTER(pointer),
        pointer,
    ]
    security.SecKeychainFindGenericPassword.restype = ctypes.c_int32
    security.SecKeychainItemFreeContent.argtypes = [pointer, pointer]
    service_bytes, account_bytes = service.encode(), account.encode()
    length, data = ctypes.c_uint32(), pointer()
    status = security.SecKeychainFindGenericPassword(
        None,
        len(service_bytes),
        service_bytes,
        len(account_bytes),
        account_bytes,
        ctypes.byref(length),
        ctypes.byref(data),
        None,
    )
    if status:
        raise RuntimeError("OpenLux credential is unavailable in macOS Keychain")
    try:
        return ctypes.string_at(data, length.value).decode()
    finally:
        security.SecKeychainItemFreeContent(None, data)


def store_keychain_secret(secret: str, service: str, account: str = "cmpys") -> None:
    """Keep the password out of command-line arguments, files, and shell history."""
    if sys.platform != "darwin":
        raise RuntimeError("Keychain credentials require macOS")
    security = ctypes.CDLL("/System/Library/Frameworks/Security.framework/Security")
    core = ctypes.CDLL(
        "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation"
    )
    pointer = ctypes.c_void_p
    uint = ctypes.c_uint32
    security.SecKeychainAddGenericPassword.argtypes = [
        pointer,
        uint,
        ctypes.c_char_p,
        uint,
        ctypes.c_char_p,
        uint,
        pointer,
        ctypes.POINTER(pointer),
    ]
    security.SecKeychainAddGenericPassword.restype = ctypes.c_int32
    security.SecKeychainFindGenericPassword.argtypes = [
        pointer,
        uint,
        ctypes.c_char_p,
        uint,
        ctypes.c_char_p,
        pointer,
        pointer,
        ctypes.POINTER(pointer),
    ]
    security.SecKeychainFindGenericPassword.restype = ctypes.c_int32
    security.SecKeychainItemModifyAttributesAndData.argtypes = [
        pointer,
        pointer,
        uint,
        pointer,
    ]
    security.SecKeychainItemModifyAttributesAndData.restype = ctypes.c_int32
    core.CFRelease.argtypes = [pointer]
    service_bytes, account_bytes, password = (
        service.encode(),
        account.encode(),
        secret.encode(),
    )
    status = security.SecKeychainAddGenericPassword(
        None,
        len(service_bytes),
        service_bytes,
        len(account_bytes),
        account_bytes,
        len(password),
        password,
        None,
    )
    if status == -25299:  # Existing credential: update only our named item.
        item = pointer()
        status = security.SecKeychainFindGenericPassword(
            None,
            len(service_bytes),
            service_bytes,
            len(account_bytes),
            account_bytes,
            None,
            None,
            ctypes.byref(item),
        )
        if status == 0:
            try:
                status = security.SecKeychainItemModifyAttributesAndData(
                    item,
                    None,
                    len(password),
                    password,
                )
            finally:
                core.CFRelease(item)
    if status:
        raise RuntimeError(f"Keychain could not store the credential (status {status})")
