"""Portable source checks; not a replacement for a full macOS/iOS build.

Run: python tools/check_spacegram_consistency.py
Optional: reuse an available PyYAML for workflow syntax checks. Use --swift-grammar with
tree-sitter and tree-sitter-swift for an advisory parser check; that grammar
does not accept all syntax in the existing Swift sources.
"""
import ast
import json
import plistlib
from pathlib import Path
import re
import struct
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
errors = []


def check(condition, message):
    if not condition:
        errors.append(message)


builds = list(ROOT.glob("SpaceGram/**/BUILD"))
builds += list(ROOT.glob("submodules/**/BUILD")) + [ROOT / "Telegram/BUILD"]
builds += list(ROOT.glob("Tests/**/BUILD"))
modules = {}
for path in builds:
    text = path.read_text(encoding="utf-8-sig")
    # These BUILD files use the Python-compatible subset of Starlark syntax.
    try:
        ast.parse(text)
    except SyntaxError as error:
        errors.append(f"BUILD syntax: {path.relative_to(ROOT)}: {error}")
    for module in re.findall(r'module_name\s*=\s*"([^"]+)"', text):
        modules[module] = path
    check("//Nagram/" not in text, f"Old package label: {path}")
    check("//Qwengram/" not in text and "Tests/Qwengram" not in text, f"Retired product package label: {path}")
    for package, target in re.findall(r'"//(SpaceGram/[^":]+)(?::([^"/]+))?"', text):
        destination = ROOT / package / "BUILD"
        check(destination.is_file(), f"Missing package {package} in {path}")
        if destination.is_file() and target and target not in ("__pkg__", "__subpackages__", "all"):
            check(re.search(r'name\s*=\s*"' + re.escape(target) + '"', destination.read_text(encoding="utf-8")),
                  f"Missing target {package}:{target} in {path}")

swift = list(ROOT.glob("SpaceGram/**/*.swift")) + list(ROOT.glob("Tests/SpaceGram*/**/*.swift"))
# Include upstream integration imports without pretending to type-check Swift.
imports = subprocess.run(
    ["rg", "-l", r"^import (Nagram|SpaceGram)", "submodules", "Telegram", "SpaceGram", "-g", "*.swift"],
    cwd=ROOT, capture_output=True, text=True, encoding="utf-8", check=False,
)
check(imports.returncode in (0, 1), f"Could not scan integration imports: {imports.stderr}")
for name in imports.stdout.splitlines():
    path = ROOT / name
    for module in re.findall(r'^import ((?:Nagram|SpaceGram)\w+)', path.read_text(encoding="utf-8"), re.M):
        check(module in modules, f"Unresolved integration module {module} in {path}")
for path in swift:
    text = path.read_text(encoding="utf-8")
    check(not re.search(r'\b(?:import|class|struct|enum|protocol|func)\s+(?:Qwengram\w*|qwengram\w*)', text),
          f"Retired Swift identifier: {path}")
    for module in re.findall(r'^import ((?:Nagram|SpaceGram)\w+)', text, re.M):
        check(module in modules, f"Unresolved module {module} in {path}")
    package = path.parent
    while package != ROOT and not (package / "BUILD").is_file():
        package = package.parent
    check(package != ROOT, f"No owning BUILD for {path}")
    if package != ROOT:
        tree = ast.parse((package / "BUILD").read_text(encoding="utf-8"))
        included = set()
        for node in ast.walk(tree):
            if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == "glob" and node.args:
                for pattern in ast.literal_eval(node.args[0]):
                    included.update(package.glob(pattern))
        check(path in included, f"Swift file not covered by source glob: {path}")

catalogs = list(ROOT.glob("SpaceGram/Strings/Strings/*.lproj/SpaceGramLocalizable.strings"))
keys = {}
for path in catalogs:
    entries = re.findall(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";', path.read_text(encoding="utf-8"), re.M)
    names = [key for key, _ in entries]
    check(len(names) == len(set(names)), f"Duplicate localization keys: {path}")
    keys[path.parent.name] = set(names)
    values = dict(entries)
    check("Nagram.Title" not in values, f"Retired product title key: {path}")
    check(not any(key.startswith("Nagram.ProfileBadge.") for key in values),
          f"Retired project-role badge strings: {path}")
    check(all("Qwengram" not in value and "QWENGRAM" not in value for value in values.values()),
          f"Legacy visible product name: {path}")
check("en.lproj" in keys and "ru.lproj" in keys, "English or Russian resource missing")
for path in swift:
    for key in re.findall(r'ngI18n\("(SpaceGram\.[^"\\]+)"', path.read_text(encoding="utf-8")):
        for locale in ("en.lproj", "ru.lproj"):
            check(key in keys.get(locale, set()), f"Missing {locale} key {key} in {path}")

loader = (ROOT / "SpaceGram/Strings/Sources/SpaceGramLocalization.swift").read_text(encoding="utf-8")
check('forResource: "SpaceGramLocalizable"' in loader, "Localization loader/resource mismatch")
app = (ROOT / "Telegram/BUILD").read_text(encoding="utf-8")
check('"//SpaceGram/Strings:SpaceGramLocalizableStrings"' in app, "App does not bundle localizations")
check('primary_app_icon = "SpaceGramAppIcon"' in app, "SpaceGram primary icon wiring changed")
check('":SpaceGramAppIconResources"' in app and '":SpaceGramAlternateAppIconResources"' in app,
      "SpaceGram icon catalog wiring changed")
info_plist = (ROOT / "Telegram/Telegram-iOS/Info.plist").read_text(encoding="utf-8")
check("Qwengram" not in info_plist, "Legacy product name in permission prompts")
check(info_plist.count("<string>SpaceGramAppIcon</string>") == 2, "Info.plist primary icon wiring changed")
check(info_plist.count("<key>Alternate</key>") == 2, "Info.plist alternate icon wiring changed")
check(not any(name in info_plist for name in ("BlackIcon", "BlackClassic", "BlackFilled", "BlueClassic", "BlueFilled", "WhiteFilled")),
      "Retired inherited alternate icon remains in Info.plist")
plistlib.loads(info_plist.encode("utf-8"))
app_delegate = (ROOT / "submodules/TelegramUI/Sources/AppDelegate.swift").read_text(encoding="utf-8")
check('PresentationAppIcon(name: "Default", imageName: "SpaceGramAppIcon", isDefault: true)' in app_delegate,
      "Default SpaceGram icon is not exposed to Appearance")
check('PresentationAppIcon(name: "Alternate", imageName: "Alternate")' in app_delegate,
      "Alternate SpaceGram icon is not exposed to Appearance")
badge_source = ROOT / "submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/NagramProfileBadge.swift"
check(not badge_source.exists(), "Retired project-role badge source remains")
for path in badge_source.parent.glob("*.swift"):
    check(not re.search(r'\b(?:NagramProfileBadge\w*|nagramProfileBadge\w*|titleNagramBadgeView|titleExpandedNagramBadgeView)\b', path.read_text(encoding="utf-8")),
          f"Dangling project-role badge reference: {path}")
check(not list((ROOT / "Telegram/Telegram-iOS").glob("Nagram*")), "Retired brand assets remain")
check(not (ROOT / "Nagram").exists(), "Old top-level source tree remains")
for path in (ROOT / "Telegram").rglob("*.strings"):
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        if "=" in line and not line.lstrip().startswith("//"):
            check("Nagram" not in line.split("=", 1)[1], f"Legacy product string in {path}")
icon_catalogs = [
    ROOT / "Telegram/Telegram-iOS/SpaceGramAppIcon.xcassets",
    ROOT / "Telegram/Telegram-iOS/SpaceGramAlternateAppIcon.xcassets",
]
check((icon_catalogs[0] / "SpaceGramAppIcon.appiconset/Contents.json").is_file(), "Primary icon catalog missing")
check((icon_catalogs[1] / "Alternate.appiconset/Contents.json").is_file(), "Alternate icon catalog missing")
for icon_catalog in icon_catalogs:
    for path in icon_catalog.rglob("Contents.json"):
        for item in json.loads(path.read_text(encoding="utf-8")).get("images", []):
            if "filename" in item:
                asset = path.parent / item["filename"]
                check(asset.is_file(), f"Missing icon asset: {path}: {item['filename']}")
                if asset.is_file():
                    png = asset.read_bytes()
                    valid_header = len(png) >= 33 and png[:8] == b"\x89PNG\r\n\x1a\n" and png[12:16] == b"IHDR"
                    check(valid_header, f"Invalid PNG header: {asset}")
                    if valid_header:
                        expected = tuple(round(float(value) * float(item["scale"].rstrip("x"))) for value in item["size"].split("x"))
                        check(struct.unpack(">II", png[16:24]) == expected, f"Incorrect icon dimensions: {asset}")
                        check(png[24:26] == bytes((8, 2)), f"Icon must be 8-bit RGB: {asset}")

try:
    import yaml
except ImportError:
    print("SKIP workflow YAML syntax: PyYAML unavailable (no dependency installed)")
else:
    for path in (ROOT / ".github/workflows").glob("*.yml"):
        data = yaml.load(path.read_text(encoding="utf-8"), Loader=yaml.BaseLoader)
        check(isinstance(data, dict) and "on" in data and "jobs" in data, f"Invalid workflow: {path}")
    print("PASS workflow YAML syntax (not GitHub Actions semantic validation)")

if "--swift-grammar" in sys.argv:
    import tree_sitter
    import tree_sitter_swift

    parser = tree_sitter.Parser(tree_sitter.Language(tree_sitter_swift.language()))
    for path in swift:
        check(not parser.parse(path.read_bytes()).root_node.has_error, f"Swift grammar error: {path}")
    print(f"Checked Swift grammar for {len(swift)} product sources (not type checking)")

for error in errors:
    print("FAIL", error)
print(f"Checked {len(builds)} BUILD files, {len(swift)} product Swift files, {len(catalogs)} catalogs; {len(errors)} errors")
sys.exit(bool(errors))
