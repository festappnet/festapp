#!/usr/bin/env python3
"""Run reviewed SQL through the Cloudflare Access protected Studio API."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import sys
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

ORIGIN = "https://supabase.festapp.net"
QUERY_URL = f"{ORIGIN}/api/platform/pg-meta/default/query?key="
MIGRATIONS = Path(__file__).resolve().parents[3] / "supabase" / "migrations"


def query(token: str, sql: str) -> list:
    request = Request(
        QUERY_URL,
        data=json.dumps({"query": sql, "disable_statement_timeout": False}).encode(),
        headers={
            "Content-Type": "application/json",
            "CF-Access-Token": token,
            "User-Agent": "Mozilla/5.0",
            "Origin": ORIGIN,
            "Referer": f"{ORIGIN}/project/default/sql",
            "X-Pg-Application-Name": "festapp-access-sql",
        },
    )
    try:
        with urlopen(request, timeout=60) as response:
            result = json.load(response)
    except HTTPError as error:
        raise RuntimeError(f"Studio SQL request failed (HTTP {error.code})") from error
    except (URLError, ValueError) as error:
        raise RuntimeError("Studio SQL request failed") from error
    if not isinstance(result, list):
        raise RuntimeError("Studio SQL returned an unexpected response")
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--expect-database", required=True)
    parser.add_argument("--token-stdin", action="store_true", help="Read an Access JWT from stdin")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true", help="Verify the target without changing it")
    mode.add_argument("--sql-file", type=Path, help="Execute an exact reviewed SQL file")
    mode.add_argument("--migration-file", type=Path, help="Apply a repository migration and ledger row atomically")
    parser.add_argument("--sha256", help="Required SHA-256 of the SQL file for execution")
    args = parser.parse_args()

    token = sys.stdin.readline().strip() if args.token_stdin else os.environ.get("FESTAPP_ACCESS_TOKEN", "")
    if not token:
        parser.error("Access token missing; use --token-stdin or FESTAPP_ACCESS_TOKEN")
    identity = query(token, "select current_database() as database_name, current_user as db_role")
    if len(identity) != 1 or identity[0].get("database_name") != args.expect_database:
        raise RuntimeError("Production database identity mismatch; no SQL file was executed")
    if args.check:
        print(json.dumps(identity[0], sort_keys=True))
        return 0

    file = args.migration_file or args.sql_file
    if not args.sha256 or not re.fullmatch(r"[0-9a-fA-F]{64}", args.sha256):
        parser.error("--sha256 is required for SQL execution")
    body = file.read_bytes()
    digest = hashlib.sha256(body).hexdigest()
    if digest != args.sha256.lower():
        raise RuntimeError("SQL file SHA-256 mismatch; no SQL was executed")
    sql = body.decode("utf-8")

    if args.migration_file:
        if file.resolve().parent != MIGRATIONS:
            raise RuntimeError("Migration must be in the canonical supabase/migrations directory")
        match = re.fullmatch(r"(\d{14})_([a-z0-9_]+)\.sql", file.name)
        if not match:
            raise RuntimeError("Migration filename must contain a version and name")
        version, name = match.groups()
        existing = query(token, f"select count(*)::int as n from supabase_migrations.schema_migrations where version='{version}'")
        if len(existing) != 1 or existing[0].get("n") != 0:
            raise RuntimeError("Migration version is already present or its state is unknown")
        sql = (
            "BEGIN;\n" + sql + "\n"
            + "INSERT INTO supabase_migrations.schema_migrations(version, statements, name) "
            + f"VALUES ('{version}', ARRAY[]::text[], '{name}');\nCOMMIT;"
        )

    result = query(token, sql)
    if args.migration_file:
        recorded = query(token, f"select count(*)::int as n from supabase_migrations.schema_migrations where version='{version}'")
        if len(recorded) != 1 or recorded[0].get("n") != 1:
            raise RuntimeError("Migration returned, but its ledger row was not verified")
        print(f"Migration {version} applied to {args.expect_database}; sha256={digest}")
    else:
        print(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(1) from error
