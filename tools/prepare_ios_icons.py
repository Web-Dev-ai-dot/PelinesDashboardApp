"""Resize the approved artwork into the existing iOS catalog (requires Pillow)."""
import json
from pathlib import Path

from PIL import Image

root = Path(__file__).resolve().parents[1]
source = root / "assets/branding/pelines_admin_icon.png"
catalog = root / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
with Image.open(source) as image:
    if image.size != (1254, 1254):
        raise SystemExit("Approved source dimensions changed; review the crop first.")
    # Remove only the 40px outer background margin containing the black rounded
    # corner matte. The P and circular artwork remain intact; no artwork is drawn.
    master = image.crop((40, 40, 1214, 1214)).convert("RGB")
    entries = json.loads((catalog / "Contents.json").read_text())["images"]
    for entry in entries:
        size = round(float(entry["size"].split("x")[0]) * int(entry["scale"][:-1]))
        master.resize((size, size), Image.Resampling.LANCZOS).save(
            catalog / entry["filename"], optimize=True
        )
print("Generated all declared iOS icon sizes from the approved source.")
