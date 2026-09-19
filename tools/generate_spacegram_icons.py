"""Prepare and render the SpaceGram app-icon collection; requires Pillow.

Run from any directory: python tools/generate_spacegram_icons.py
Only deterministic crop, resize, sRGB normalization and metadata cleanup are
performed. Source artwork under Branding/SpaceGram/IconSources is never edited.
"""
import json
import sys
from pathlib import Path

from PIL import Image, ImageCms, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "Branding/SpaceGram/IconSources"
PREPARED = ROOT / "Branding/SpaceGram/PreparedIcons"
APP = ROOT / "Telegram/Telegram-iOS"
PRIMARY_SET = APP / "SpaceGramAppIcon.xcassets/SpaceGramAppIcon.appiconset"
ALTERNATE_CATALOG = APP / "SpaceGramAlternateAppIcon.xcassets"
PROFILE = ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB")).tobytes()
MASTER_SIZE = (1024, 1024)

# Crop boxes are (left, top, right, bottom), measured in the untouched
# 1254-by-1254 source PNGs. The planet variants share the same inner tile but
# have minor one-to-three-pixel export differences at its edges.
ICONS = (
    {
        "name": "Default",
        "source": "SpaceGram-Alternate.png",
        "prepared": "SpaceGram-Alternate.png",
        "crop": None,
        "catalog": "SpaceGramAppIcon",
        "prefix": "SpaceGram",
        "preview": "SpaceGramIconDefaultPreview.png",
        "default": True,
    },
    {"name": "Moon", "source": "Moon.png", "crop": (130, 117, 1122, 1109)},
    {"name": "Earth", "source": "Earth.png", "crop": (127, 111, 1122, 1106)},
    {"name": "Mars", "source": "Mars.png", "crop": (130, 118, 1122, 1110)},
    {"name": "Sun", "source": "Sun.png", "crop": (130, 117, 1121, 1108)},
    {"name": "Saturn", "source": "Saturn.png", "crop": (129, 117, 1121, 1109)},
    {"name": "Neptune", "source": "Neptune.png", "crop": (130, 118, 1122, 1110)},
)

RENDITIONS = (
    ("iphone", "20x20", "2x", 40),
    ("iphone", "20x20", "3x", 60),
    ("iphone", "29x29", "2x", 58),
    ("iphone", "29x29", "3x", 87),
    ("iphone", "40x40", "2x", 80),
    ("iphone", "40x40", "3x", 120),
    ("iphone", "60x60", "2x", 120),
    ("iphone", "60x60", "3x", 180),
    ("ipad", "20x20", "1x", 20),
    ("ipad", "20x20", "2x", 40),
    ("ipad", "29x29", "1x", 29),
    ("ipad", "29x29", "2x", 58),
    ("ipad", "40x40", "1x", 40),
    ("ipad", "40x40", "2x", 80),
    ("ipad", "76x76", "2x", 152),
    ("ipad", "83.5x83.5", "2x", 167),
    ("ios-marketing", "1024x1024", "1x", 1024),
)


def normalized_icon(icon):
    result = dict(icon)
    result.setdefault("prepared", icon["source"])
    result.setdefault("catalog", icon["name"])
    result.setdefault("prefix", f"SpaceGram-{icon['name']}")
    result.setdefault("preview", f"SpaceGramIcon{icon['name']}Preview.png")
    result.setdefault("default", False)
    return result


def save_rgb(image, path, size=MASTER_SIZE):
    image = image.convert("RGB")
    if image.size != size:
        image = image.resize(size, Image.Resampling.LANCZOS)
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG", optimize=True, icc_profile=PROFILE)


def prepare(icon):
    source_path = SOURCES / icon["source"]
    with Image.open(source_path) as source:
        if source.size != (1254, 1254):
            raise ValueError(f"{icon['name']}: expected a 1254x1254 source, got {source.size}")
        if source.mode not in ("RGB", "RGBA"):
            raise ValueError(f"{icon['name']}: source must be RGB/RGBA, got {source.mode}")
        artwork = source.crop(icon["crop"]) if icon["crop"] else source.copy()
        if artwork.width != artwork.height:
            raise ValueError(f"{icon['name']}: crop must be square, got {artwork.size}")
        destination = PREPARED / icon["prepared"]
        save_rgb(artwork, destination)
        return destination


def rendition_filename(prefix, size, scale, idiom):
    point_size = size.split("x", 1)[0]
    suffix = "-ipad" if idiom == "ipad" and scale == "2x" and point_size in ("20", "29", "40") else ""
    scale_suffix = "" if scale == "1x" else f"@{scale}"
    return f"{prefix}-{point_size}{scale_suffix}{suffix}.png"


def contents(prefix):
    images = []
    for idiom, size, scale, _ in RENDITIONS:
        images.append({
            "filename": rendition_filename(prefix, size, scale, idiom),
            "idiom": idiom,
            "scale": scale,
            "size": size,
        })
    return {"images": images, "info": {"author": "xcode", "version": 1}}


def render_renditions(master, icon):
    directory = PRIMARY_SET if icon["default"] else ALTERNATE_CATALOG / f"{icon['catalog']}.appiconset"
    directory.mkdir(parents=True, exist_ok=True)
    manifest = contents(icon["prefix"])
    with (directory / "Contents.json").open("w", encoding="utf-8", newline="\n") as manifest_file:
        json.dump(manifest, manifest_file, indent=2)
        manifest_file.write("\n")
    count = 0
    with Image.open(master) as source:
        for item, (_, _, _, pixels) in zip(manifest["images"], RENDITIONS):
            save_rgb(source, directory / item["filename"], (pixels, pixels))
            count += 1
    return count


def render_regular_resources(masters):
    resources = APP / "Resources"
    for icon, master in zip(ICONS, masters):
        icon = normalized_icon(icon)
        with Image.open(master) as source:
            save_rgb(source, resources / icon["preview"], (180, 180))
            if icon["default"]:
                save_rgb(source, resources / "SpaceGramSettings.png", (87, 87))
                save_rgb(source, resources / "SpaceGramWelcome.png", (444, 444))


def render_contact_sheet(masters):
    tile_size = 256
    label_height = 44
    margin = 20
    sheet = Image.new("RGB", (margin * 2 + tile_size * len(masters), margin * 2 + tile_size + label_height), "#161616")
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default(size=20)
    for index, (icon, master) in enumerate(zip(ICONS, masters)):
        icon = normalized_icon(icon)
        with Image.open(master) as source:
            preview = source.convert("RGB").resize((tile_size, tile_size), Image.Resampling.LANCZOS)
        x = margin + index * tile_size
        sheet.paste(preview, (x, margin))
        label_box = draw.textbbox((0, 0), icon["name"], font=font)
        label_width = label_box[2] - label_box[0]
        draw.text((x + (tile_size - label_width) / 2, margin + tile_size + 10), icon["name"], fill="white", font=font)
    save_rgb(sheet, PREPARED / "SpaceGram-Icon-Contact-Sheet.png", sheet.size)


def main():
    normalized = tuple(normalized_icon(icon) for icon in ICONS)
    masters = [prepare(icon) for icon in normalized]
    render_regular_resources(masters)
    render_contact_sheet(masters)
    if "--previews-only" in sys.argv:
        print(f"Prepared {len(masters)} masters, regular previews and contact sheet")
        return
    count = sum(render_renditions(master, icon) for icon, master in zip(normalized, masters))
    print(f"Prepared {len(masters)} masters and rendered {count} app-icon renditions, regular previews and contact sheet")


if __name__ == "__main__":
    main()
