"""Portable integration contracts; not Swift compilation or device tests."""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class SpaceGramFeatureContracts(unittest.TestCase):
    def test_no_foreign_user_facing_branding(self):
        forbidden = re.compile(r"Nagram|NGram|AyuGram|AuraGram|Qwengram|Qwen", re.I)
        for path in (ROOT / "SpaceGram/Strings/Strings").glob("*.lproj/SpaceGramLocalizable.strings"):
            entries = re.findall(r'^"(?:[^"\\]|\\.)*"\s*=\s*"((?:[^"\\]|\\.)*)";', path.read_text(encoding="utf-8"), re.M)
            self.assertFalse([value for value in entries if forbidden.search(value)], path)

        active_ui = [
            ROOT / "SpaceGram/SettingsUI",
            ROOT / "SpaceGram/Bots",
            ROOT / "submodules/GalleryUI/Sources/Items",
        ]
        for directory in active_ui:
            for path in directory.glob("*.swift"):
                source = path.read_text(encoding="utf-8")
                self.assertNotIn("查看信息", source, path)
                if directory.name in ("SettingsUI", "Bots"):
                    self.assertNotIn("Qwen", source, path)

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
        preview_names = ("Default", "Moon", "Earth", "Mars", "Sun", "Saturn", "Neptune")
        for name in ("SpaceGramSettings",) + tuple(f"SpaceGramIcon{icon}Preview" for icon in preview_names):
            path = ROOT / f"Telegram/Telegram-iOS/Resources/{name}.png"
            self.assertEqual(path.read_bytes()[:8], b"\x89PNG\r\n\x1a\n")
        build = (ROOT / "Telegram/BUILD").read_text(encoding="utf-8")
        self.assertIn("Telegram-iOS/Resources/**", build)

    def test_spacegram_icon_collection_contract(self):
        app_delegate = (ROOT / "submodules/TelegramUI/Sources/AppDelegate.swift").read_text(encoding="utf-8")
        info_plist = (ROOT / "Telegram/Telegram-iOS/Info.plist").read_text(encoding="utf-8")
        for name in ("Moon", "Earth", "Mars", "Sun", "Saturn", "Neptune"):
            self.assertIn(f'PresentationAppIcon(name: "{name}"', app_delegate)
            self.assertEqual(info_plist.count(f"<key>{name}</key>"), 2)
        self.assertIn('PresentationAppIcon(name: "Default"', app_delegate)
        self.assertNotIn('PresentationAppIcon(name: "Alternate"', app_delegate)
        self.assertNotIn("<key>Alternate</key>", info_plist)

    def test_startup_order_is_preserved(self):
        source = (ROOT / "SpaceGram/SettingsSignal/Sources/SpaceGramSettingsSignal.swift").read_text(encoding="utf-8")
        self.assertLess(source.index("_ = SpaceGramSettings.shared"), source.index("NotificationCenter.default.addObserver"))

    def test_formatter_default_and_legacy_key_are_preserved(self):
        source = (ROOT / "SpaceGram/Enhancements/Settings/NagramSettings.swift").read_text(encoding="utf-8")
        self.assertIn('@NagramDefault("nagram.showTextStyleToolbar", false)', source)
        wrapper = source[:source.index("public enum")]
        self.assertIn("object(forKey:", wrapper)

    def test_advanced_screen_russian_labels(self):
        source = (ROOT / "SpaceGram/Enhancements/SettingsUI/NagramSettingsController.swift").read_text(encoding="utf-8")
        keys = set(re.findall(r'(?:titleKey|headerKey|footerKey): "([^"]+)"', source))
        catalog = (ROOT / "SpaceGram/Strings/Strings/ru.lproj/SpaceGramLocalizable.strings").read_text(encoding="utf-8")
        translated = set(re.findall(r'^"([^"]+)"\s*=', catalog, re.M))
        self.assertFalse(keys - translated, keys - translated)

    def test_delayed_send_preserves_native_schedule_and_call_exception(self):
        source = (ROOT / "submodules/TelegramUI/Sources/ChatController.swift").read_text(encoding="utf-8")
        hook = source[source.index("func spaceGramDelayedMessages"):source.index("func sendMessages(_ messages:")]
        self.assertIn("OutgoingScheduleInfoMessageAttribute", hook)
        self.assertIn("!attributes.contains", hook)
        self.assertNotIn("Timer(", hook)
        self.assertIn("context.account.network.globalTime", hook)
        composer = (ROOT / "submodules/TelegramUI/Sources/Chat/ChatControllerLoadDisplayNode.swift").read_text(encoding="utf-8")
        self.assertIn("spaceGramDelayedMessages(strongSelf.transformEnqueueMessages", composer)
        self.assertIn("var shouldOpenScheduledMessages = delayedMessages.1", composer)
        self.assertIn("strongSelf.openScheduledMessages(force: true", composer)
        activity = (ROOT / "submodules/TelegramCore/Sources/State/ManagedLocalInputActivities.swift").read_text(encoding="utf-8")
        self.assertIn("if !isSpeakingInGroupCall(activity)", activity)

    def test_delayed_send_revalidates_after_upload(self):
        attribute = (ROOT / "submodules/TelegramCore/Sources/SyncCore/SyncCore_OutgoingScheduleInfoMessageAttribute.swift").read_text(encoding="utf-8")
        self.assertIn("spaceGramMinimumDelay: Int32? = nil", attribute)
        self.assertIn('decodeOptionalInt32ForKey("sgmd")', attribute)
        self.assertIn("max(spaceGramDelayedSendMinimumInterval, minimumDelay)", attribute)

        chat = (ROOT / "submodules/TelegramUI/Sources/ChatController.swift").read_text(encoding="utf-8")
        self.assertIn("spaceGramMinimumDelay: spaceGramDelayedSendMinimumInterval", chat)

        pending = (ROOT / "submodules/TelegramCore/Sources/State/PendingMessageManager.swift").read_text(encoding="utf-8")
        standalone = (ROOT / "submodules/TelegramCore/Sources/PendingMessages/StandaloneSendMessage.swift").read_text(encoding="utf-8")
        self.assertEqual(pending.count("scheduleDate: requestScheduleTime"), 6)
        self.assertEqual(standalone.count("scheduleDate: requestScheduleTime"), 6)
        self.assertNotIn("scheduleDate: scheduleTime", pending)
        self.assertNotIn("scheduleDate: scheduleTime", standalone)
        self.assertIn("currentServerTime: network.globalTime", pending)

    def test_ghost_presence_and_activity_send_boundaries(self):
        presence = (ROOT / "submodules/TelegramCore/Sources/State/ManagedAccountPresence.swift").read_text(encoding="utf-8")
        self.assertIn("online && !suppressed", presence)
        self.assertIn("self.onlineTimer?.invalidate()", presence)
        self.assertEqual(presence.count("Api.functions.account.updateStatus"), 2)

        activity = (ROOT / "submodules/TelegramCore/Sources/State/ManagedLocalInputActivities.swift").read_text(encoding="utf-8")
        self.assertIn("combineLatest(activities, spaceGramSuppressChatActivitySignal())", activity)
        self.assertIn("if SpaceGramGhostPolicy.suppressChatActivity", activity)
        self.assertIn("if !isSpeakingInGroupCall(activity)", activity)

    def test_ghost_quick_button_uses_the_persisted_master(self):
        settings = (ROOT / "SpaceGram/Settings/SpaceGramSettings.swift").read_text(encoding="utf-8")
        chat_list = (ROOT / "submodules/ChatListUI/Sources/ChatListController.swift").read_text(encoding="utf-8")
        delayed = (ROOT / "submodules/TelegramUI/Sources/ChatController.swift").read_text(encoding="utf-8")
        self.assertIn('@SpaceGramDefault("spacegram.settings.ghostModeEnabled", false)', settings)
        self.assertIn("ghostModeEnabled = enabled", settings)
        self.assertIn("SpaceGramSettings.shared.ghostMode.enabled", chat_list)
        self.assertNotIn("SpaceGramSettings.shared.ghostMode.isFull", chat_list)
        self.assertIn("guard settings.ghostMode.enabled, settings.delayedSend", delayed)


if __name__ == "__main__":
    unittest.main()
