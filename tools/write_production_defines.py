"""Validate the production release and write ephemeral Flutter client defines."""
import argparse
import base64
import json
import os
from pathlib import Path
import re
import subprocess

PROJECT_REF = "yoolmwqgjftqmcxriwnx"
EXPECTED = {
    "APP_ENV": "production",
    "API_BASE_URL": "https://pelines-api.aiwithtalha.com/v1",
    "SUPABASE_URL": f"https://{PROJECT_REF}.supabase.co",
}
ROOT = Path(__file__).resolve().parents[1]


def client_key():
    key = os.environ.get("PELINES_PRODUCTION_SUPABASE_ANON_KEY", "")
    if re.fullmatch(r"sb_publishable_[A-Za-z0-9_-]{20,}", key):
        return key
    if re.fullmatch(r"[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+", key):
        payload = key.split(".")[1]
        try:
            claims = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
        except ValueError:
            claims = None
        if isinstance(claims, dict) and claims.get("role") == "anon" and claims.get("ref") == PROJECT_REF:
            return key
    raise SystemExit("Expected a production Supabase anon or publishable client key.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    for name, expected in EXPECTED.items():
        if os.environ.get(name) != expected:
            raise SystemExit(f"{name} must match the production configuration.")
    version = os.environ.get("RELEASE_VERSION", "")
    build = os.environ.get("RELEASE_BUILD_NUMBER", "")
    if not re.fullmatch(r"(0|[1-9][0-9]*)(\.(0|[1-9][0-9]*)){2}", version):
        raise SystemExit("Set RELEASE_VERSION after checking App Store Connect.")
    if not re.fullmatch(r"[1-9][0-9]*", build):
        raise SystemExit("Set RELEASE_BUILD_NUMBER above the last App Store Connect build.")
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    if any(os.environ.get(name) for name in ("DEMO_USER_ID", "DEMO_USER_EMAIL")):
        raise SystemExit("Demo overrides are forbidden in this release workflow.")
    key = client_key()
    print(f"Verified production destinations, version {version}, build {build}, commit {head}.")
    if args.check:
        return
    path = ROOT / "build/ios-ci/production-defines.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as output:
        json.dump({**EXPECTED, "SUPABASE_ANON_KEY": key}, output)


if __name__ == "__main__":
    main()
