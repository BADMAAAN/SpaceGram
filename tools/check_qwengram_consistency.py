"""Portable source checks; not a replacement for a full macOS/iOS build.

Run: python tools/check_qwengram_consistency.py
Optional: install PyYAML for workflow syntax checks. Use --swift-grammar with
tree-sitter and tree-sitter-swift for an advisory parser check; that grammar
does not accept all syntax in the existing Swift sources.
"""
import ast
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
errors = []


def check(condition, message):
    if not condition:
        errors.append(message)


builds = list(ROOT.glob("Qwengram/**/BUILD"))
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
    for package, target in re.findall(r'"//(Qwengram/[^":]+)(?::([^"/]+))?"', text):
        destination = ROOT / package / "BUILD"
        check(destination.is_file(), f"Missing package {package} in {path}")
        if destination.is_file() and target and target not in ("__pkg__", "__subpackages__", "all"):
            check(re.search(r'name\s*=\s*"' + re.escape(target) + '"', destination.read_text(encoding="utf-8")),
                  f"Missing target {package}:{target} in {path}")

swift = list(ROOT.glob("Qwengram/**/*.swift"))
# Include upstream integration imports without pretending to type-check Swift.
imports = subprocess.run(
    ["rg", "-l", r"^import (Nagram|Qwengram)", "submodules", "Telegram", "Qwengram", "-g", "*.swift"],
    cwd=ROOT, capture_output=True, text=True, encoding="utf-8", check=False,
)
check(imports.returncode in (0, 1), f"Could not scan integration imports: {imports.stderr}")
for name in imports.stdout.splitlines():
    path = ROOT / name
    for module in re.findall(r'^import ((?:Nagram|Qwengram)\w+)', path.read_text(encoding="utf-8"), re.M):
        check(module in modules, f"Unresolved integration module {module} in {path}")
for path in swift:
    text = path.read_text(encoding="utf-8")
    for module in re.findall(r'^import ((?:Nagram|Qwengram)\w+)', text, re.M):
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

catalogs = list(ROOT.glob("Qwengram/Strings/Strings/*.lproj/QwengramLocalizable.strings"))
keys = {}
for path in catalogs:
    entries = re.findall(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";', path.read_text(encoding="utf-8"), re.M)
    names = [key for key, _ in entries]
    check(len(names) == len(set(names)), f"Duplicate localization keys: {path}")
    keys[path.parent.name] = set(names)
    check(dict(entries).get("Nagram.Title") in (None, "Qwengram"), f"Legacy display title: {path}")
check("en.lproj" in keys and "ru.lproj" in keys, "English or Russian resource missing")
for path in swift:
    for key in re.findall(r'ngI18n\("(Qwengram\.[^"\\]+)"', path.read_text(encoding="utf-8")):
        for locale in ("en.lproj", "ru.lproj"):
            check(key in keys.get(locale, set()), f"Missing {locale} key {key} in {path}")

loader = (ROOT / "Qwengram/Strings/Sources/QwengramLocalization.swift").read_text(encoding="utf-8")
check('forResource: "QwengramLocalizable"' in loader, "Localization loader/resource mismatch")
app = (ROOT / "Telegram/BUILD").read_text(encoding="utf-8")
check('"//Qwengram/Strings:QwengramLocalizableStrings"' in app, "App does not bundle localizations")
check('primary_app_icon = "AppIconLLC"' in app and 'app_icons = [":DefaultAppIcon"]' in app, "Primary icon wiring changed; review checker")
check(not list((ROOT / "Telegram/Telegram-iOS").glob("Nagram*")), "Retired brand assets remain")
check(not (ROOT / "Nagram").exists(), "Old top-level source tree remains")
for path in (ROOT / "Telegram").rglob("*.strings"):
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        if "=" in line and not line.lstrip().startswith("//"):
            check("Nagram" not in line.split("=", 1)[1], f"Legacy product string in {path}")
for path in (ROOT / "Telegram/Telegram-iOS/DefaultAppIcon.xcassets").rglob("Contents.json"):
    for item in json.loads(path.read_text(encoding="utf-8")).get("images", []):
        if "filename" in item:
            check((path.parent / item["filename"]).is_file(), f"Missing icon asset: {path}: {item['filename']}")

try:
    import yaml
except ImportError:
    print("SKIP workflow YAML syntax: install PyYAML")
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
