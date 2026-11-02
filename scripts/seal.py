"""Seal a secret to a GitHub Actions public key.

Usage: seal.py <base64 public key> < value
Prints the base64 sealed box that GitHub's secrets API (and the provider's
encrypted_value) expects.

The value is read from stdin as-is, except that a one-line value loses its
trailing newline. That newline comes from the command that printed the value
(`atticadm make-token`, `agenix -d`), not the secret, and a token sent in an
HTTP header with it fails (`InvalidHeaderValue`). Multi-line values, such as
SSH private keys, keep theirs: OpenSSH needs it.

Fails on empty stdin: in a pipeline like `(cmd) | just seal ...`, a failing
`cmd` leaves stdin empty, and sealing that would replace a secret with "".
"""

import base64
import sys

from nacl import encoding, public

value = sys.stdin.buffer.read()
if not value.strip():
    sys.exit("seal: nothing on stdin; did the command feeding it fail?")

if value.count(b"\n") == 1 and value.endswith(b"\n"):
    value = value[:-1]

key = public.PublicKey(sys.argv[1].encode(), encoding.Base64Encoder())
sealed = public.SealedBox(key).encrypt(value)
print(base64.b64encode(sealed).decode())
