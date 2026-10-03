#!/usr/bin/env python3
"""Synthetic S3 seed, authorization probe, benchmark and recovery client."""

from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
import math
import os
import random
import socket
import sys
import time
from datetime import datetime, timezone
from typing import Any

import boto3
from botocore import UNSIGNED
from botocore.client import Config
from botocore.exceptions import BotoCoreError, ClientError


FIXTURE = b"research-landing-zone-v1\n"
MIB = 1024 * 1024
OBJECT_COUNT = 32
OBJECT_SIZE = 4 * MIB
FIXTURE_SHA256 = hashlib.sha256(FIXTURE).hexdigest()


def emit(row: dict[str, Any]) -> None:
    row["utc"] = datetime.now(timezone.utc).isoformat()
    print(json.dumps(row, sort_keys=True), flush=True)


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def s3_client(*, anonymous: bool = False):
    if not os.environ.get("S3_ENDPOINT"):
        raise ValueError("S3_ENDPOINT is required")
    if not anonymous and not (
        os.environ.get("AWS_ACCESS_KEY_ID") and os.environ.get("AWS_SECRET_ACCESS_KEY")
    ):
        raise ValueError("role S3 credentials are missing from the client Pod")
    config = Config(
        connect_timeout=2,
        read_timeout=5,
        max_pool_connections=8,
        retries={"mode": "standard", "total_max_attempts": 1},
        s3={"addressing_style": "path"},
        signature_version=UNSIGNED if anonymous else "s3v4",
    )
    return boto3.client(
        "s3",
        endpoint_url=os.environ["S3_ENDPOINT"],
        region_name="us-east-1",
        config=config,
    )


def operation(
    s3,
    op: str,
    bucket: str,
    key: str = "fixture.txt",
    body: bytes = FIXTURE,
    expected: str | None = None,
) -> dict[str, Any]:
    started = time.perf_counter()
    row: dict[str, Any] = {
        "op": op,
        "bucket": bucket,
        "key": key,
        "principal": os.environ.get("PRINCIPAL", "unspecified"),
        "ok": False,
        "bytes": 0,
        "http": None,
        "error": None,
    }
    try:
        if op == "put":
            response = s3.put_object(Bucket=bucket, Key=key, Body=body)
            row["bytes"] = len(body)
        elif op == "get":
            response = s3.get_object(Bucket=bucket, Key=key)
            stream = response["Body"]
            try:
                data = stream.read()
            finally:
                stream.close()
            row["bytes"] = len(data)
        elif op == "list":
            response = s3.list_objects_v2(Bucket=bucket, Prefix=key)
            row["keys"] = [item["Key"] for item in response.get("Contents", [])]
        elif op == "delete":
            response = s3.delete_object(Bucket=bucket, Key=key)
        else:
            raise ValueError(f"unsupported operation: {op}")

        # Per-request latency stops after response/body handling and before local hashing.
        row["ms"] = 1000 * (time.perf_counter() - started)
        metadata = response["ResponseMetadata"]
        row.update(
            http=metadata["HTTPStatusCode"],
            ok=True,
            request_id=metadata.get("RequestId"),
        )
        if op == "get":
            row["sha256"] = digest(data)
            if expected is not None:
                row["hash_ok"] = row["sha256"] == expected
                row["ok"] = row["ok"] and row["hash_ok"]
    except ClientError as exc:
        metadata = exc.response.get("ResponseMetadata", {})
        error = exc.response.get("Error", {})
        row.update(
            http=metadata.get("HTTPStatusCode"),
            error=error.get("Code", "ClientError"),
            request_id=metadata.get("RequestId"),
        )
    except (BotoCoreError, OSError, ValueError) as exc:
        row["error"] = type(exc).__name__
    row.setdefault("ms", 1000 * (time.perf_counter() - started))
    return row


def seed(s3) -> bool:
    all_ok = True
    for bucket in ("research-raw", "research-release"):
        try:
            s3.head_bucket(Bucket=bucket)
        except ClientError as exc:
            status = exc.response.get("ResponseMetadata", {}).get("HTTPStatusCode")
            if status != 404:
                emit(
                    {
                        "op": "head_bucket",
                        "bucket": bucket,
                        "ok": False,
                        "http": status,
                        "error": exc.response.get("Error", {}).get("Code", "ClientError"),
                    }
                )
                return False
            try:
                s3.create_bucket(Bucket=bucket)
            except ClientError as create_error:
                emit(
                    {
                        "op": "create_bucket",
                        "bucket": bucket,
                        "ok": False,
                        "http": create_error.response.get("ResponseMetadata", {}).get("HTTPStatusCode"),
                        "error": create_error.response.get("Error", {}).get("Code", "ClientError"),
                    }
                )
                return False
        for key in ("fixture.txt", "delete-probe.txt"):
            row = operation(s3, "put", bucket, key, FIXTURE)
            emit(row)
            all_ok = all_ok and row["ok"]
    emit({"kind": "seed_summary", "buckets": 2, "objects": 4, "success": all_ok})
    return all_ok


def nearest_rank_p95(values: list[float]) -> float | None:
    if not values:
        return None
    return sorted(values)[math.ceil(0.95 * len(values)) - 1]


def payloads() -> list[bytes]:
    # A fresh seeded PRNG per index makes every object deterministic and distinct.
    return [random.Random(index).randbytes(OBJECT_SIZE) for index in range(OBJECT_COUNT)]


def benchmark(s3, concurrency: int, prefix: str) -> bool:
    if concurrency not in (1, 4):
        raise ValueError("lab concurrency must be 1 or 4")
    values = payloads()
    hashes = [digest(value) for value in values]
    trial_ok = True
    for phase in ("put", "get"):
        def one(index: int) -> dict[str, Any]:
            return operation(
                s3,
                phase,
                "research-raw",
                f"{prefix}/{index:03d}.bin",
                values[index],
                hashes[index] if phase == "get" else None,
            )

        started = time.perf_counter()
        with concurrent.futures.ThreadPoolExecutor(max_workers=concurrency) as pool:
            rows = list(pool.map(one, range(OBJECT_COUNT)))
        elapsed = time.perf_counter() - started
        for row in rows:
            emit({**row, "run": prefix, "concurrency": concurrency})
        good = [row for row in rows if row["ok"]]
        trial_ok = trial_ok and len(good) == OBJECT_COUNT
        emit(
            {
                "kind": "summary",
                "run": prefix,
                "phase": phase,
                "concurrency": concurrency,
                "n": OBJECT_COUNT,
                "successes": len(good),
                "success_ratio": len(good) / OBJECT_COUNT,
                "wall_s": elapsed,
                "goodput_MiB_s": sum(row["bytes"] for row in good) / MIB / elapsed if elapsed else 0,
                "p95_success_ms": nearest_rank_p95([row["ms"] for row in good]),
            }
        )
    return trial_ok


def verify(s3, prefix: str) -> bool:
    values = payloads()
    verified = 0
    for index, value in enumerate(values):
        row = operation(
            s3,
            "get",
            "research-raw",
            f"{prefix}/{index:03d}.bin",
            expected=digest(value),
        )
        emit(row)
        verified += int(row["ok"])
    success = verified == OBJECT_COUNT
    emit(
        {
            "kind": "verified",
            "objects": verified,
            "expected": OBJECT_COUNT,
            "prefix": prefix,
            "success": success,
        }
    )
    return success


def watch(s3, seconds: int) -> None:
    if seconds <= 0:
        raise ValueError("watch duration must be positive")
    started = time.perf_counter()
    while time.perf_counter() - started < seconds:
        offset = time.perf_counter() - started
        row = operation(s3, "get", "research-raw", "fixture.txt", expected=FIXTURE_SHA256)
        emit({**row, "start_s": offset, "end_s": time.perf_counter() - started})
        time.sleep(1)


def tcp_probe(host: str, port: int) -> bool:
    row: dict[str, Any] = {"host": host, "port": port, "tcp_connected": False}
    started = time.perf_counter()
    try:
        addresses = socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)
        row["dns_resolved"] = True
        row["resolved_addresses"] = sorted({entry[4][0] for entry in addresses})
    except socket.gaierror as exc:
        row.update(dns_resolved=False, dns_error=type(exc).__name__)
        row["seconds"] = time.perf_counter() - started
        emit(row)
        return False
    try:
        with socket.create_connection((host, port), timeout=3):
            row["tcp_connected"] = True
    except OSError as exc:
        row["error"] = type(exc).__name__
    row["seconds"] = time.perf_counter() - started
    emit(row)
    return row["tcp_connected"]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="mode", required=True)
    subparsers.add_parser("seed")
    probe_parser = subparsers.add_parser("probe")
    probe_parser.add_argument("operation", choices=("put", "get", "list", "delete"))
    probe_parser.add_argument("bucket")
    probe_parser.add_argument("key")
    probe_parser.add_argument("anonymous", nargs="?", choices=("anon",))
    bench_parser = subparsers.add_parser("bench")
    bench_parser.add_argument("concurrency", type=int)
    bench_parser.add_argument("prefix")
    verify_parser = subparsers.add_parser("verify")
    verify_parser.add_argument("prefix")
    watch_parser = subparsers.add_parser("watch")
    watch_parser.add_argument("seconds", type=int)
    tcp_parser = subparsers.add_parser("tcp")
    tcp_parser.add_argument("host")
    tcp_parser.add_argument("port", type=int)
    args = parser.parse_args()

    try:
        if args.mode == "tcp":
            return 0 if tcp_probe(args.host, args.port) else 2
        client = s3_client(anonymous=getattr(args, "anonymous", None) == "anon")
        if args.mode == "seed":
            return 0 if seed(client) else 2
        if args.mode == "probe":
            expected = FIXTURE_SHA256 if args.operation == "get" and args.key == "fixture.txt" else None
            row = operation(client, args.operation, args.bucket, args.key, expected=expected)
            if args.anonymous == "anon":
                row["principal"] = "anonymous"
            emit(row)
            return 0 if row["ok"] else 2
        if args.mode == "bench":
            return 0 if benchmark(client, args.concurrency, args.prefix) else 2
        if args.mode == "verify":
            return 0 if verify(client, args.prefix) else 2
        if args.mode == "watch":
            watch(client, args.seconds)
            return 0
    except (ValueError, BotoCoreError) as exc:
        print(f"helper error: {type(exc).__name__}", file=sys.stderr)
        return 2
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
