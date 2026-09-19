# SpaceGram icon sources

The source PNGs in this directory are immutable artwork inputs:

- `SpaceGram-Alternate.png` — the default SpaceGram app icon;
- `Moon.png`, `Earth.png`, `Mars.png`, `Sun.png`, `Saturn.png`, and
  `Neptune.png` — alternate app icons.

`SpaceGram-Primary.png` was intentionally removed and must not be restored.

Run `python tools/generate_spacegram_icons.py` with Pillow available. The
generator never edits these files. It writes normalized 1024-by-1024 RGB/sRGB
masters to `../PreparedIcons/`, generates the non-production contact sheet,
updates the app-icon catalogs, and renders the regular picker/welcome assets.

The six planet sources contain a rounded-square artwork tile surrounded by a
black presentation canvas. Their crop boxes are recorded in the generator and
in `SpaceGram/SPACEGRAM_BRANDING_AUDIT.md`. Only crop, proportional Lanczos
resize, sRGB normalization, and metadata cleanup are performed. No mask,
frame, border, inpainting, or generative edit is added.

The checked-in catalogs contain 17 current iPhone, iPad, and App Store slots
per icon. The obsolete iPad `76x76@1x` slot is intentionally absent.
