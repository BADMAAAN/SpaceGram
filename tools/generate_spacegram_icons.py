"""Render existing full-bleed SpaceGram masters; requires Pillow.

Run from any directory: python tools/generate_spacegram_icons.py
No masking, padding, framing or AI generation is performed here.
"""
import json
import sys
from pathlib import Path

from PIL import Image, ImageCms

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "Branding/SpaceGram/IconSources"
APP = ROOT / "Telegram/Telegram-iOS"
PROFILE = ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB")).tobytes()


def render(image, path, size):
    image.resize(size, Image.Resampling.LANCZOS).save(path, icc_profile=PROFILE)


def main():
    count = 0
    for variant, catalog in (
        ("Primary", "SpaceGramAppIcon.xcassets/SpaceGramAppIcon.appiconset"),
        ("Alternate", "SpaceGramAlternateAppIcon.xcassets/Alternate.appiconset"),
    ):
        with Image.open(SOURCES / f"SpaceGram-{variant}.png") as source:
            if source.width != source.height or source.mode != "RGB":
                raise ValueError(f"{variant}: master must be an opaque RGB square")
            directory = APP / catalog
            contents = json.loads((directory / "Contents.json").read_text(encoding="utf-8"))
            # Regular resources are reliably loadable by UIImage. App-icon sets
            # are compiled for SpringBoard, not general-purpose image lookup.
            render(source, APP / f"Resources/SpaceGramIcon{variant}Preview.png", (180, 180))
            if variant == "Primary":
                render(source, APP / "Resources/SpaceGramSettings.png", (87, 87))
            if "--previews-only" in sys.argv:
                continue
            for item in contents["images"]:
                scale = float(item["scale"].rstrip("x"))
                size = tuple(round(float(value) * scale) for value in item["size"].split("x"))
                render(source, directory / item["filename"], size)
                count += 1
            if variant == "Primary":
                # 148-point welcome logo at 3x, loaded by RMIntro via AppResources.
                render(source, APP / "Resources/SpaceGramWelcome.png", (444, 444))
    print("Rendered settings and icon previews" if "--previews-only" in sys.argv else f"Rendered {count} app-icon renditions, welcome and previews")


if __name__ == "__main__":
    main()
