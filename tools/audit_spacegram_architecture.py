"""Regenerate source inventories; read-only except SpaceGram/audits outputs.

Counts case-insensitive literal 'nagram' occurrences, including comments/keys.
Uses Git's tracked + nonignored untracked file inventory; does not inspect Git
objects, the user's patch, signing material, binaries, or nested submodule trees.
Generated inventories are excluded to avoid self-counting. No file is deleted.
"""
from collections import Counter
import csv
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "SpaceGram/audits"


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT).decode("utf-8")


def write_tsv(name, header, rows):
    with (OUT / name).open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t", lineterminator="\n")
        writer.writerow(header)
        writer.writerows(rows)


def main():
    OUT.mkdir(exist_ok=True)
    tracked = set(filter(None, git("ls-files", "-z").split("\0")))
    untracked = set(filter(None, git("ls-files", "--others", "--exclude-standard", "-z").split("\0")))
    files = sorted(tracked | untracked)
    references, legacy_references, dependencies, imports, targets = [], [], [], [], []
    category_counts = Counter()
    directory_counts = Counter()
    skipped = Counter()
    for name in files:
        path = ROOT / name
        if not path.is_file() or path.is_symlink():
            continue
        directory_counts[name.split("/")[0]] += 1
        if name.startswith("SpaceGram/audits/"):
            skipped["generated inventories"] += 1
            continue
        if (name == "qwengram_run7_fix.patch" or name.startswith("build-input/")
                or any(part in name.lower() for part in ("codesigning", "provisioning", "credentials"))
                or path.suffix.lower() in (".p12", ".p8", ".pem", ".key", ".mobileprovision")):
            skipped["protected inputs"] += 1
            continue
        data = path.read_bytes()
        if b"\0" in data:
            skipped["binary"] += 1
            continue
        try:
            text = data.decode("utf-8-sig")
        except UnicodeDecodeError:
            skipped["non-UTF8"] += 1
            continue
        for line_number, line in enumerate(text.splitlines(), 1):
            legacy_count = len(re.findall("qwengram", line, re.I))
            if legacy_count:
                if "C:\\Project\\Qwengram" in line or "/approved/Qwengram" in line:
                    legacy_category = "C: preserved checkout/root path"
                elif path.suffix == ".md":
                    legacy_category = "B: historical documentation or compatibility explanation"
                elif path.suffix == ".swift" and name.startswith(("SpaceGram/", "Tests/SpaceGram")):
                    legacy_category = "A: migration fixture / compatibility storage contract"
                elif name.startswith("tools/"):
                    legacy_category = "A: legacy-reference regression guard / protected user artifact"
                elif name.startswith(".github/"):
                    legacy_category = "D: existing branch / bundle ID / CI secret contract"
                else:
                    legacy_category = "E: requires review"
                legacy_references.append((name, line_number, legacy_count, legacy_category))
            count = len(re.findall("nagram", line, re.I))
            if not count:
                continue
            stripped = line.strip()
            if path.suffix == ".md":
                category = "documentation / attribution / historical audit"
            elif path.suffix == ".strings":
                category = "localization compatibility key or provider disclosure"
            elif path.name in ("BUILD", "BUILD.bazel"):
                category = "Bazel module / dependency / provenance"
            elif stripped.startswith(("//", "/*", "*", "#", "<!--")):
                category = "comment / rebase marker / provenance"
            elif path.suffix in (".swift", ".m", ".mm", ".h"):
                category = "active code / compatibility or external contract"
            else:
                category = "tooling / configuration / other"
            references.append((name, line_number, count, category))
            category_counts[category] += count
        if path.name in ("BUILD", "BUILD.bazel"):
            for label in re.findall(r'"(//SpaceGram/Enhancements/[^"\n]+)"', text):
                dependencies.append((name, label))
            if name.startswith(("SpaceGram/", "Tests/SpaceGram")):
                for target in re.findall(r'\bname\s*=\s*"([^"\n]+)"', text):
                    targets.append((name, "//" + path.parent.relative_to(ROOT).as_posix() + ":" + target))
        if path.suffix == ".swift":
            for module in re.findall(r'^import (Nagram\w+)', text, re.M):
                imports.append((name, module))
    write_tsv("remaining-nagram-references.tsv", ("file", "line", "occurrences", "classification"), references)
    write_tsv("remaining-qwengram-references.tsv", ("file", "line", "occurrences", "classification"), legacy_references)
    write_tsv("enhancement-dependencies.tsv", ("consumer_build", "dependency"), sorted(dependencies))
    write_tsv("enhancement-imports.tsv", ("consumer_source", "module"), sorted(imports))
    write_tsv("spacegram-targets.tsv", ("build_file", "target"), sorted(targets))
    summary = {
        "head": git("rev-parse", "HEAD").strip(),
        "scope": "parent Git tracked + nonignored untracked text; excludes audit outputs, user patch, signing/private inputs, binary/non-UTF8, symlinks, nested submodule contents",
        "reference_occurrences": sum(row[2] for row in references),
        "legacy_occurrences_by_category": dict(sorted(Counter({category: sum(row[2] for row in legacy_references if row[3] == category) for category in {row[3] for row in legacy_references}}).items())),
        "reference_lines": len(references),
        "reference_files": len({row[0] for row in references}),
        "occurrences_by_category": dict(sorted(category_counts.items())),
        "enhancement_dependency_edges": len(dependencies),
        "swift_imports_by_module": dict(sorted(Counter(module for _, module in imports).items())),
        "product_and_test_targets": len(targets),
        "existing_file_counts_by_top_level": dict(sorted(directory_counts.items())),
        "excluded_file_counts": dict(sorted(skipped.items())),
        "untracked": sorted(untracked),
    }
    (OUT / "spacegram-inventory.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps({key: summary[key] for key in ("reference_occurrences", "reference_lines", "reference_files", "occurrences_by_category", "enhancement_dependency_edges", "swift_imports_by_module", "product_and_test_targets")}, indent=2))


if __name__ == "__main__":
    main()
