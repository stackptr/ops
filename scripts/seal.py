"""Seal a secret to a GitHub Actions public key.

Usage: seal.py <base64 public key> < value
Prints the base64 sealed box that GitHub's secrets API (and the provider's
encrypted_value) expects. The value is read from stdin as-is.
"""

import base64
import sys

from nacl import encoding, public

key = public.PublicKey(sys.argv[1].encode(), encoding.Base64Encoder())
sealed = public.SealedBox(key).encrypt(sys.stdin.buffer.read())
print(base64.b64encode(sealed).decode())
