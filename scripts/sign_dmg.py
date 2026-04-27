#!/usr/bin/env python3
"""Sign a DMG with Ed25519 (Sparkle 2.x compatible).

Reads the base64 private-key seed from $SPARKLE_PRIVATE_KEY, signs the
raw bytes of the DMG passed as argv[1], and prints the base64-encoded
64-byte signature on stdout.

Sparkle's sign_update tool produces the same signature; using Python
here keeps the macOS runner free of a Sparkle install (the native tool
lives inside the Sparkle.app bundle and isn't trivially fetchable).
"""
import base64
import os
import sys
from pathlib import Path

try:
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
    from cryptography.hazmat.primitives import serialization
except ImportError:
    sys.exit("cryptography not installed — run `pip install cryptography` first")


def main() -> int:
    if len(sys.argv) != 2:
        sys.exit("usage: sign_dmg.py <path-to-dmg>")
    dmg = Path(sys.argv[1])
    if not dmg.is_file():
        sys.exit(f"file not found: {dmg}")

    secret = os.environ.get("SPARKLE_PRIVATE_KEY")
    if not secret:
        sys.exit("SPARKLE_PRIVATE_KEY env var must be set (base64-encoded "
                 "32-byte Ed25519 seed)")
    seed = base64.b64decode(secret)
    if len(seed) != 32:
        sys.exit(f"private key must decode to 32 bytes, got {len(seed)}")

    priv = Ed25519PrivateKey.from_private_bytes(seed)
    sig = priv.sign(dmg.read_bytes())
    print(base64.b64encode(sig).decode())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
