#!/usr/bin/env python3
"""Create private, bucket-scoped SeaweedFS S3 credentials without printing them."""

from __future__ import annotations

import argparse
import json
import os
import secrets
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PRIVATE = ROOT / "private"
REDACTED = ROOT / "policies-redacted.json"
POLICIES = {
    "owner": ["Admin", "Read", "Write", "List"],
    "ingestor": ["Read:research-raw", "Write:research-raw", "List:research-raw"],
    "analyst": ["Read:research-release", "List:research-release"],
}


def write_private(path: Path, content: str, *, replace: bool) -> None:
    if path.exists() and not replace:
        raise FileExistsError(f"{path.relative_to(ROOT)} already exists; use --rotate only when key rotation is intended")
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        os.chmod(path, 0o600)
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rotate", action="store_true", help="replace existing credentials; update Secrets and restart storage after rotation")
    args = parser.parse_args()

    PRIVATE.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(PRIVATE, 0o700)
    if REDACTED.exists() and not args.rotate:
        print(f"Refusing to overwrite {REDACTED.name}; use --rotate only for an intentional key rotation.", file=sys.stderr)
        return 2

    identities = []
    environment_files: dict[str, str] = {}
    for role, actions in POLICIES.items():
        access_key = "lab-" + secrets.token_hex(10)
        secret_key = secrets.token_urlsafe(32)
        identities.append(
            {
                "name": role,
                "actions": actions,
                "credentials": [{"accessKey": access_key, "secretKey": secret_key}],
            }
        )
        environment_files[f"{role}.env"] = (
            f"AWS_ACCESS_KEY_ID={access_key}\nAWS_SECRET_ACCESS_KEY={secret_key}\n"
        )

    config = json.dumps({"identities": identities}, indent=2) + "\n"
    redacted = json.dumps(POLICIES, indent=2) + "\n"
    targets = [PRIVATE / "s3.json", *(PRIVATE / name for name in environment_files)]
    existing = [path.name for path in targets if path.exists()]
    if existing and not args.rotate:
        print(f"Refusing to replace existing private outputs: {', '.join(existing)}; use --rotate only for an intentional rotation.", file=sys.stderr)
        return 2

    try:
        for name, content in environment_files.items():
            write_private(PRIVATE / name, content, replace=args.rotate)
        write_private(PRIVATE / "s3.json", config, replace=args.rotate)
        REDACTED.write_text(redacted, encoding="utf-8")
    except OSError as exc:
        print(f"Could not write identity files: {exc}", file=sys.stderr)
        return 2

    print("Generated unique credentials for owner, ingestor and analyst.")
    print("Private credentials are mode 0600 under private/; no credential values were printed.")
    if args.rotate:
        print("Rotation requested: update all Kubernetes Secrets and restart storage before use.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
