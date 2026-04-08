#!/usr/bin/env python3
"""Generate GCP OAuth2 access token from service account JSON (ADC key file)."""
import json, time, base64, urllib.request, urllib.parse, os, sys

cred_file = os.environ.get('GOOGLE_APPLICATION_CREDENTIALS', '')
if not cred_file or not os.path.exists(cred_file):
    print("Error: GOOGLE_APPLICATION_CREDENTIALS not set or file not found", file=sys.stderr)
    sys.exit(1)

with open(cred_file) as f:
    sa = json.load(f)

if sa.get('type') != 'service_account':
    print(f"Error: credential type '{sa.get('type')}' is not service_account", file=sys.stderr)
    sys.exit(1)

try:
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import padding
except ImportError:
    print("Error: python3-cryptography is required", file=sys.stderr)
    sys.exit(1)


def b64url(data):
    if isinstance(data, str):
        data = data.encode()
    return base64.urlsafe_b64encode(data).rstrip(b'=')


now = int(time.time())
token_uri = sa.get('token_uri', 'https://oauth2.googleapis.com/token')

header = b64url(json.dumps({"alg": "RS256", "typ": "JWT"}, separators=(',', ':')))
payload = b64url(json.dumps({
    "iss": sa['client_email'],
    "sub": sa['client_email'],
    "aud": token_uri,
    "scope": "https://www.googleapis.com/auth/cloud-platform",
    "iat": now,
    "exp": now + 3600,
}, separators=(',', ':')))

msg = header + b'.' + payload
key = serialization.load_pem_private_key(sa['private_key'].encode(), password=None)
sig = b64url(key.sign(msg, padding.PKCS1v15(), hashes.SHA256()))
jwt_token = msg + b'.' + sig

post_data = urllib.parse.urlencode({
    'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
    'assertion': jwt_token.decode(),
}).encode()

try:
    req = urllib.request.Request(token_uri, data=post_data)
    with urllib.request.urlopen(req, timeout=10) as resp:
        result = json.loads(resp.read())
    print(result['access_token'])
except Exception as e:
    print(f"Error fetching token: {e}", file=sys.stderr)
    sys.exit(1)
