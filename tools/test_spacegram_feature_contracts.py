"""Portable integration contracts; not Swift compilation or device tests."""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class SpaceGramFeatureContracts(unittest.TestCase):
    def test_single_root_entry(self):
        source = (ROOT / "submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoSettingsItems.swift").read_text(encoding="utf-8")
        self.assertEqual(source.count('text: "SpaceGram"'), 1)
        self.assertNotIn('text: "SpaceGram · Telegram"', source)
        self.assertIn("icon: spaceGramSettingsIcon()", source)

    def test_hub_identities_and_localization(self):
        source = (ROOT / "SpaceGram/SettingsUI/SpaceGramSettingsController.swift").read_text(encoding="utf-8")
        ids = [int(value) for value in re.findall(r"\b(?:link|toggle|footer)\((\d+),", source)]
        ids += [int(value) * 100 for value in re.findall(r"\bheader\((\d+),", source)]
        self.assertEqual(len(ids), len(set(ids)), "ItemList identities must be unique")
        self.assertIn("entries: entries.sorted()", source, "ItemList requires strictly ordered entries")
        keys = set(re.findall(r'"(SpaceGram\.[^"]+)"', source))
        for locale in ("en", "ru"):
            catalog = (ROOT / f"SpaceGram/Strings/Strings/{locale}.lproj/SpaceGramLocalizable.strings").read_text(encoding="utf-8")
            entries = dict(re.findall(r'^"([^"]+)"\s*=\s*"((?:[^"\\]|\\.)*)";', catalog, re.M))
            self.assertFalse(keys - entries.keys(), f"{locale}: missing {keys - entries.keys()}")
            if locale == "ru":
                for key in keys:
                    self.assertRegex(entries[key], "[А-Яа-яЁё]", key)

    def test_preview_resources_are_packaged(self):
        for name in ("SpaceGramSettings", "SpaceGramIconPrimaryPreview", "SpaceGramIconAlternatePreview"):
            path = ROOT / f"Telegram/Telegram-iOS/Resources/{name}.png"
            self.assertEqual(path.read_bytes()[:8], b"\x89PNG\r\n\x1a\n")
        build = (ROOT / "Telegram/BUILD").read_text(encoding="utf-8")
        self.assertIn("Telegram-iOS/Resources/**", build)

    def test_startup_order_is_preserved(self):
        source = (ROOT / "SpaceGram/SettingsSignal/Sources/SpaceGramSettingsSignal.swift").read_text(encoding="utf-8")
        self.assertLess(source.index("_ = SpaceGramSettings.shared"), source.index("NotificationCenter.default.addObserver"))


if __name__ == "__main__":
    unittest.main()
