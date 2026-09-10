"""Write CI-only client configuration without logging any key values."""
import json
import os
from pathlib import Path
import sys


def main():
    expected = {
        "APP_ENV": "staging",
        "API_BASE_URL": "https://pelines-api-staging.aiwithtalha.com/v1",
        "SUPABASE_URL": "https://qrtuwjpofwtefueqtokp.supabase.co",
    }
    values = {name: os.environ.get(name, "") for name in (*expected, "SUPABASE_ANON_KEY")}
    for name, value in expected.items():
        if values[name] != value:
            raise SystemExit(f"{name} must match the documented staging configuration.")
    key = values["SUPABASE_ANON_KEY"]
    if len(key) < 24 or not key.startswith(("eyJ", "sb_publishable_")):
        raise SystemExit("SUPABASE_ANON_KEY must be the staging anon/publishable client key.")
    if key.startswith("eyJ"):
        import base64

        try:
            payload = key.split(".")[1]
            claims = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
        except (ValueError, IndexError):
            raise SystemExit("SUPABASE_ANON_KEY is not a valid client-key JWT.") from None
        if claims.get("role") != "anon" or claims.get("ref") != "qrtuwjpofwtefueqtokp":
            raise SystemExit("The client-key JWT must be anon and belong to staging.")
    # Always under ignored build/, never an arbitrary path or tracked env file.
    path = Path(__file__).resolve().parents[1] / "build/ios-ci/staging-defines.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(values), encoding="utf-8")
    if sys.platform != "win32":
        path.chmod(0o600)
    print("Ephemeral staging client configuration generated (values redacted).")


if __name__ == "__main__":
    main()
