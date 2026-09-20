import json
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import spacegram_build_info as build_info


class BuildIdentityTests(unittest.TestCase):
    def check_identity(self, embedded_sha, expected_sha, dirty=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            stamp = root / "stamp.plist"
            identity = {"SpaceGramSourceSHA": "a" * 40, "SpaceGramSourceDirty": dirty, "SpaceGramBuildTime": "2026-09-20T00:00:00+00:00"}
            stamp.write_bytes(plistlib.dumps(identity))
            embedded = dict(identity, SpaceGramSourceSHA=embedded_sha, CFBundleVersion="15", CFBundleShortVersionString="1.0")
            ipa = root / "fixture.ipa"
            with zipfile.ZipFile(ipa, "w") as archive:
                archive.writestr("Payload/SpaceGram.app/Info.plist", plistlib.dumps(embedded))
            report = root / "build-info.json"
            with patch.object(build_info, "STAMP", stamp):
                build_info.verify(ipa, report, expected_sha)
            return json.loads(report.read_text(encoding="utf-8"))

    def test_matches_ipa_identity_and_preserves_dirty(self):
        report = self.check_identity("a" * 40, "a" * 40, dirty=True)
        self.assertTrue(report["SpaceGramSourceDirty"])
        self.assertEqual(report["CFBundleVersion"], "15")

    def test_rejects_an_ipa_from_another_revision(self):
        with self.assertRaisesRegex(RuntimeError, "source SHA"):
            self.check_identity("b" * 40, "a" * 40)

    def test_rejects_stamp_mismatch_even_when_expected_sha_matches(self):
        with self.assertRaisesRegex(RuntimeError, "build information"):
            self.check_identity("b" * 40, "b" * 40)


if __name__ == "__main__":
    unittest.main()
