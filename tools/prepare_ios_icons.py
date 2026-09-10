"""Generate iOS and Android icons from approved artwork, without cropping (Pillow)."""
import json
import math
from pathlib import Path

from PIL import Image

root = Path(__file__).resolve().parents[1]
source = root / "assets/branding/pelines_admin_icon.png"
catalog = root / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
res = root / "android/app/src/main/res"

with Image.open(source) as image:
    artwork = image.convert("RGBA")


def canvas(size, *, safe_circle=None, transparent=False):
    # Preserve aspect ratio and every source pixel. Existing Android background
    # is black; iOS requires an opaque square. No rounded corners are baked in.
    ratio = size / max(artwork.size)
    if safe_circle is not None:
        ratio = safe_circle / math.hypot(*artwork.size)
    dimensions = tuple(max(1, round(axis * ratio)) for axis in artwork.size)
    scaled = artwork.resize(dimensions, Image.Resampling.LANCZOS)
    result = Image.new("RGBA", (size, size), (0, 0, 0, 0 if transparent else 255))
    result.alpha_composite(scaled, ((size - scaled.width) // 2, (size - scaled.height) // 2))
    return result if transparent else result.convert("RGB")


entries = json.loads((catalog / "Contents.json").read_text())["images"]
for entry in entries:
    size = round(float(entry["size"].split("x")[0]) * int(entry["scale"][:-1]))
    canvas(size).save(catalog / entry["filename"], optimize=True)

for density, factor in {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}.items():
    folder = res / f"mipmap-{density}"
    size = round(48 * factor)
    canvas(size).save(folder / "ic_launcher.png", optimize=True)
    canvas(size, safe_circle=size * 0.9).save(folder / "ic_launcher_round.png", optimize=True)
    # Android's adaptive foreground is 108dp, with the artwork inside its 66dp
    # safe circle so launcher masks do not clip the supplied design.
    canvas(round(108 * factor), safe_circle=66 * factor, transparent=True).save(
        folder / "ic_launcher_foreground.png", optimize=True
    )
print("Generated all declared iOS sizes and all five Android launcher densities.")
