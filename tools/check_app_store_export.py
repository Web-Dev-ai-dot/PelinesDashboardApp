"""Validate the effective Codemagic export plist before building."""
import argparse
from pathlib import Path
import plistlib


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("plist", type=Path)
    args = parser.parse_args()
    try:
        with args.plist.open("rb") as source:
            options = plistlib.load(source)
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        raise SystemExit("Could not read the effective export options plist.") from error

    if not isinstance(options, dict):
        raise SystemExit("The effective export options must be a plist dictionary.")
    if options.get("testFlightInternalTestingOnly", False) is not False:
        raise SystemExit("The effective export options enable or misconfigure TestFlight Internal Only.")
    if (
        options.get("method") not in ("app-store", "app-store-connect")
        or options.get("teamID") != "B4YBH74VKG"
        or options.get("destination") != "export"
    ):
        raise SystemExit("Expected App Store Connect export for team B4YBH74VKG.")
    print("Verified App Store Connect export for team B4YBH74VKG. Internal-only mode is off.")


if __name__ == "__main__":
    main()
