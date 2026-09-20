"""Stamp the build before Bazel, then verify the identity inside the resulting IPA."""
import argparse
import datetime
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
STAMP = ROOT / "Telegram/SpaceGramBuildInfo.plist"


def checkout_sha():
    directory = ROOT / ".git"
    if directory.is_file():
        directory = (ROOT / directory.read_text().strip().removeprefix("gitdir: ")).resolve()
    head = (directory / "HEAD").read_text().strip()
    if not head.startswith("ref: "):
        return head
    ref = head[5:]
    loose = directory / ref
    if loose.is_file():
        return loose.read_text().strip()
    packed = directory / "packed-refs"
    for line in packed.read_text().splitlines() if packed.is_file() else []:
        if line.endswith(" " + ref):
            return line.split()[0]
    raise RuntimeError("Cannot resolve checkout SHA")


def prepare():
    sha = checkout_sha()
    if not re.fullmatch(r"[0-9a-f]{40}", sha):
        raise RuntimeError("Invalid source SHA")
    if os.environ.get("GITHUB_ACTIONS") == "true":
        if sha != os.environ.get("GITHUB_SHA"):
            raise RuntimeError("Workflow SHA does not match checkout")
        dirty = False  # checkout step, before any generated build inputs
    else:
        jj = shutil.which("jj")
        if jj is None:
            raise RuntimeError("Local builds require jj in PATH to identify dirty sources")
        sha = subprocess.check_output([jj, "log", "-r", "@-", "--no-graph", "-T", "commit_id"], cwd=ROOT, text=True).strip()
        changed = subprocess.check_output([jj, "diff", "--name-only"], cwd=ROOT, text=True).splitlines()
        dirty = any(p.replace("\\", "/") != "Telegram/SpaceGramBuildInfo.plist" for p in changed)
    data = {
        "SpaceGramSourceSHA": sha,
        "SpaceGramSourceDirty": dirty,
        "SpaceGramBuildTime": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
    }
    STAMP.write_bytes(plistlib.dumps(data))
    return data


def verify(ipa, output, expected_sha):
    expected = plistlib.loads(STAMP.read_bytes())
    with zipfile.ZipFile(ipa) as archive:
        names = [n for n in archive.namelist() if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", n)]
        if len(names) != 1:
            raise RuntimeError("Expected exactly one main app plist")
        embedded = plistlib.loads(archive.read(names[0]))
    if embedded.get("SpaceGramSourceSHA") != expected_sha:
        raise RuntimeError("IPA source SHA differs from the requested revision")
    for key, value in expected.items():
        if embedded.get(key) != value:
            raise RuntimeError("IPA build information does not match build inputs: " + key)
    report = dict(expected)
    for key in ("CFBundleShortVersionString", "CFBundleVersion", "CFBundleIdentifier", "CFBundleDisplayName"):
        report[key] = embedded.get(key)
    Path(output).write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ipa")
    parser.add_argument("--output")
    parser.add_argument("--expected-sha")
    args = parser.parse_args()
    if args.ipa:
        verify(args.ipa, args.output, args.expected_sha)
    else:
        prepare()
