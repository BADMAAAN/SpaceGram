import io
import plistlib
import struct
import tempfile
import unittest
import zipfile
from pathlib import Path

from inspect_spacegram_ipa import inspect, profile_entitlements, signed_entitlements


def macho(entitlements):
    xml = plistlib.dumps(entitlements)
    slot = struct.pack(">II", 0xfade7171, 8 + len(xml)) + xml
    blob = struct.pack(">IIIII", 0xfade0cc0, 20 + len(slot), 1, 5, 20) + slot
    header = struct.pack("<8I", 0xfeedfacf, 0x100000c, 0, 2, 1, 16, 0, 0)
    return header + struct.pack("<4I", 0x1d, 16, 48, len(blob)) + blob


class IPAInspectionTests(unittest.TestCase):
    def test_signed_slot_is_separate_from_profile(self):
        self.assertEqual(signed_entitlements(macho({"aps-environment": "development"})), [{"aps-environment": "development"}])
        profile = b"CMS" + plistlib.dumps({"Entitlements": {"aps-environment": "production"}}) + b"trailer"
        self.assertEqual(profile_entitlements(profile)["Entitlements"]["aps-environment"], "production")

    def test_fat_binary_reports_each_architecture(self):
        arm = macho({"application-identifier": "TEAM.app"})
        data = struct.pack(">7I", 0xcafebabe, 1, 0x100000c, 0, 28, len(arm), 0) + arm
        self.assertEqual(signed_entitlements(data), [{"application-identifier": "TEAM.app"}])

    def test_nested_artifact_preserves_extension_identity_and_input(self):
        ipa = io.BytesIO()
        with zipfile.ZipFile(ipa, "w") as archive:
            for bundle, bundle_id, extension in [("Payload/App.app", "app", None), ("Payload/App.app/PlugIns/Notification.appex", "app.Notification", "com.apple.usernotifications.service")]:
                info = {"CFBundleIdentifier": bundle_id, "CFBundleExecutable": "Executable"}
                if extension:
                    info["NSExtension"] = {"NSExtensionPointIdentifier": extension}
                archive.writestr(bundle + "/Info.plist", plistlib.dumps(info))
                archive.writestr(bundle + "/Executable", macho({"application-identifier": "TEAM." + bundle_id}))
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "artifact.zip"
            with zipfile.ZipFile(path, "w") as archive:
                archive.writestr("Telegram.ipa", ipa.getvalue())
            original = path.read_bytes()
            result = inspect(path)
            self.assertEqual(path.read_bytes(), original)
            self.assertEqual(len(result["bundles"]), 2)
            self.assertEqual(result["bundles"][1]["extension_point"], "com.apple.usernotifications.service")

    def test_malformed_input_fails_loudly(self):
        with self.assertRaises(ValueError):
            signed_entitlements(b"invalid")
        with self.assertRaises(ValueError):
            profile_entitlements(b"no plist")


if __name__ == "__main__":
    unittest.main()
