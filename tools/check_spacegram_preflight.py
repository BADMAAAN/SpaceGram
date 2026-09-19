"""Windows/macOS source preflight. Not Swift type checking or Bazel analysis.

Run python tools/check_spacegram_preflight.py; optionally reuse installed
tree-sitter, tree-sitter-swift and PyYAML. No packages are installed by this tool.
"""
import ast
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
import plistlib

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--report", type=Path, default=ROOT / "SpaceGram/audits/overnight-preflight.json")
args = parser.parse_args()
errors = []
report = {}


def check(condition, message):
    if not condition:
        errors.append(message)


result = subprocess.run([sys.executable, str(ROOT / "tools/check_spacegram_consistency.py")], cwd=ROOT)
check(result.returncode == 0, "Consistency checker failed")
plists = list((ROOT / "Telegram").rglob("*.plist"))
fragments = []
for path in plists:
    try:
        data = path.read_bytes()
        # Upstream AddAlternateIcons.sh imports these XML dictionaries as
        # fragments; they are not complete Info.plist files.
        if path.relative_to(ROOT).as_posix() in ("Telegram/Telegram-iOS/AlternateIcons.plist", "Telegram/Telegram-iOS/AlternateIcons-iPad.plist"):
            data = b'<?xml version="1.0"?><plist version="1.0">' + data + b'</plist>'
            fragments.append(path.relative_to(ROOT).as_posix())
        plistlib.loads(data)
    except Exception as error:
        errors.append(f"Invalid plist {path.relative_to(ROOT)}: {error}")
report["plists"] = len(plists)
report["plist_fragments"] = fragments

catalogs = list((ROOT / "Telegram").rglob("Contents.json"))
assets = 0
for path in catalogs:
    try:
        value = json.loads(path.read_text(encoding="utf-8-sig"))
        for section in ("images", "data", "colors"):
            for item in value.get(section, []):
                if "filename" in item:
                    assets += 1
                    check((path.parent / item["filename"]).is_file(), f"Missing asset: {path.relative_to(ROOT)} / {item['filename']}")
    except Exception as error:
        errors.append(f"Invalid catalog {path.relative_to(ROOT)}: {error}")
report.update(asset_catalog_json=len(catalogs), asset_files=assets)

source_paths = set()
for build in (ROOT / "SpaceGram").rglob("BUILD"):
    tree = ast.parse(build.read_text(encoding="utf-8-sig"))
    for node in tree.body:
        if not isinstance(node, ast.Expr) or not isinstance(node.value, ast.Call):
            continue
        for keyword in node.value.keywords:
            if keyword.arg != "srcs":
                continue
            included = []
            if isinstance(keyword.value, ast.Call) and getattr(keyword.value.func, "id", None) == "glob":
                for pattern in ast.literal_eval(keyword.value.args[0]):
                    included.extend(build.parent.glob(pattern))
            elif isinstance(keyword.value, ast.List):
                for name in ast.literal_eval(keyword.value):
                    if name.startswith((":", "//", "@")):
                        continue
                    path = build.parent / name
                    check(path.is_file(), f"Dangling source: {build.relative_to(ROOT)} / {name}")
                    included.append(path)
            check(len(included) == len(set(included)), f"Duplicate source in {build.relative_to(ROOT)}")
            source_paths.update(str(path.relative_to(ROOT)) for path in included)
report["owned_source_paths"] = len(source_paths)
check(not (ROOT / "Qwengram").exists(), "Old product source tree remains")

# Swift grammar is advisory: record actual nodes, including known grammar gaps,
# without mislabelling this as a successful Swift compilation.
try:
    import tree_sitter
    import tree_sitter_swift
except ImportError:
    report["swift_grammar"] = "SKIPPED: parser unavailable"
else:
    parser = tree_sitter.Parser(tree_sitter.Language(tree_sitter_swift.language()))
    diagnostics = []
    sources = list((ROOT / "SpaceGram").rglob("*.swift")) + list((ROOT / "Tests/SpaceGramMediaArchiveTests").glob("*.swift"))
    for path in sources:
        data = path.read_bytes()
        stack = [parser.parse(data).root_node]
        while stack:
            node = stack.pop()
            if node.type == "ERROR" or node.is_missing:
                diagnostics.append(dict(file=path.relative_to(ROOT).as_posix(), line=node.start_point[0] + 1,
                                        kind=node.type, missing=node.is_missing,
                                        text=data[node.start_byte:node.end_byte].decode("utf-8", errors="replace")[:120]))
            stack.extend(reversed(node.children))
    report["swift_grammar"] = dict(files=len(sources), advisory_diagnostics=diagnostics)
    print(f"ADVISORY Swift grammar: {len(diagnostics)} nodes in {len({d['file'] for d in diagnostics})} files; inspect audit, not compiler diagnostics")

# Includes legacy bundle IDs/secrets as intentional contracts; only source paths
# and imports are forbidden. Historical documents/fixtures are audited separately.
scan = subprocess.run(["rg", "-n", r"//Qwengram/|Tests/Qwengram|import Qwengram|QwengramLocalizable",
                       "SpaceGram", "Telegram", "submodules", "Tests", ".github",
                       "-g", "BUILD", "-g", "*.bzl", "-g", "*.swift", "-g", "*.yml"],
                      cwd=ROOT, capture_output=True, text=True, encoding="utf-8")
check(scan.returncode == 1, "Old active source references: " + scan.stdout + scan.stderr)
try:
    import yaml
except ImportError:
    report["yaml"] = "SKIPPED: PyYAML unavailable"
else:
    workflows = list((ROOT / ".github/workflows").glob("*.yml")) + [ROOT / ".gitlab-ci.yml"]
    for path in workflows:
        try:
            check(isinstance(yaml.load(path.read_text(encoding="utf-8"), Loader=yaml.BaseLoader), dict), f"Invalid YAML mapping: {path}")
        except yaml.YAMLError as error:
            errors.append(f"Invalid YAML: {path}: {error}")
    report["yaml"] = len(workflows)

report["errors"] = errors
out = args.report
out.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
for error in errors:
    print("FAIL", error)
print(f"Preflight: {len(plists)} plists, {len(catalogs)} asset JSONs, {assets} asset files; {len(errors)} errors")
sys.exit(bool(errors))
