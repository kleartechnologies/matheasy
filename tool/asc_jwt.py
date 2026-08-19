"""Mint an App Store Connect API JWT (ES256) using only openssl + stdlib.

Usage: python3 asc_jwt.py <key_id> <issuer_id> <p8_path>
Prints the JWT to stdout.
"""
import base64
import json
import subprocess
import sys
import time


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_to_raw(der: bytes) -> bytes:
    """Convert an openssl DER ECDSA signature to the raw 64-byte R||S JWT form."""
    assert der[0] == 0x30
    idx = 2 if der[1] < 0x80 else 2 + (der[1] & 0x7F)

    def read_int(i):
        assert der[i] == 0x02
        length = der[i + 1]
        val = der[i + 2 : i + 2 + length]
        return val.lstrip(b"\x00"), i + 2 + length

    r, idx = read_int(idx)
    s, _ = read_int(idx)
    return r.rjust(32, b"\x00") + s.rjust(32, b"\x00")


key_id, issuer_id, p8_path = sys.argv[1], sys.argv[2], sys.argv[3]
now = int(time.time())
header = b64url(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}).encode())
payload = b64url(
    json.dumps(
        {"iss": issuer_id, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"}
    ).encode()
)
signing_input = f"{header}.{payload}".encode()
der = subprocess.run(
    ["openssl", "dgst", "-sha256", "-sign", p8_path],
    input=signing_input,
    capture_output=True,
    check=True,
).stdout
print(f"{header}.{payload}.{b64url(der_to_raw(der))}")
