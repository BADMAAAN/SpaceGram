"""Portable integration contracts; not Swift compilation or device tests."""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class SpaceGramFeatureContracts(unittest.TestCase):
    def test_retired_spacegram_ai_layer_is_absent(self):
        self.assertFalse(any((ROOT / "SpaceGram/AI").glob("*")))
        self.assertFalse((ROOT / "SpaceGram/SettingsUI/SpaceGramAIRichText.swift").exists())
        settings = (ROOT / "SpaceGram/Settings/SpaceGramSettings.swift").read_text(encoding="utf-8")
        tests_build = (ROOT / "Tests/SpaceGramMediaArchiveTests/BUILD").read_text(encoding="utf-8")
        bots = (ROOT / "SpaceGram/Bots/SpaceGramBotDescriptor.swift").read_text(encoding="utf-8")
        self.assertNotRegex(settings, r"qwenModel|aiContextCharacters")
        self.assertNotIn("//SpaceGram/AI", tests_build)
        self.assertNotIn("case ai", bots)

    def test_custom_qr_is_absent_and_telegram_qr_remains(self):
        self.assertFalse(any((ROOT / "SpaceGram/QR").glob("*")))
        self.assertFalse((ROOT / "SpaceGram/SettingsUI/SpaceGramQRToolsController.swift").exists())
        settings_ui = "\n".join(path.read_text(encoding="utf-8") for path in (ROOT / "SpaceGram/SettingsUI").glob("*.swift"))
        self.assertNotRegex(settings_ui, r"QR Tools|Generate QR|SpaceGramQR")
        peer_info = (ROOT / "submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreen.swift").read_text(encoding="utf-8")
        shared_context = (ROOT / "submodules/TelegramUI/Sources/SharedAccountContext.swift").read_text(encoding="utf-8")
        self.assertIn("openQrCode:", peer_info)
        self.assertIn("makeChatQrCodeScreen", shared_context)

    def test_ci_sigtrap_retry_is_bounded_and_evidence_gated(self):
        workflow = (ROOT / ".github/workflows/spacegram-ios-test.yml").read_text(encoding="utf-8")
        self.assertEqual(workflow.count("run_test_attempt 2"), 1)
        self.assertIn("Executed [0-9]+ tests?, with 0 failures", workflow)
        self.assertIn("Child process terminated with signal 5: Trace/BPT trap", workflow)
        self.assertIn('if [ "$test_status" -ne 0 ]', workflow)
        self.assertIn('exit "$test_status"', workflow)
        self.assertNotIn("continue-on-error", workflow)

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

    def test_active_product_localization_has_english_and_russian(self):
        catalogs = {}
        for locale in ("en", "ru"):
            source = (ROOT / f"SpaceGram/Strings/Strings/{locale}.lproj/SpaceGramLocalizable.strings").read_text(encoding="utf-8")
            catalogs[locale] = set(re.findall(r'^"([^"]+)"\s*=', source, re.M))

        used = set()
        for path in (ROOT / "SpaceGram").rglob("*.swift"):
            used.update(re.findall(r'"((?:SpaceGram|Nagram)\.[A-Za-z0-9_.-]+)"', path.read_text(encoding="utf-8")))
        localizable = used & (catalogs["en"] | catalogs["ru"])
        for locale in ("en", "ru"):
            self.assertFalse(localizable - catalogs[locale], f"{locale}: missing {localizable - catalogs[locale]}")

    def test_delayed_send_preserves_native_schedule_and_call_exception(self):
        source = (ROOT / "submodules/TelegramUI/Sources/ChatController.swift").read_text(encoding="utf-8")
        hook = source[source.index("func spaceGramDelayedMessages"):source.index("func sendMessages(_ messages:")]
        self.assertIn("OutgoingScheduleInfoMessageAttribute", hook)
        self.assertIn("!attributes.contains", hook)
        self.assertNotIn("Timer(", hook)
        self.assertIn("context.account.network.globalTime", hook)
        composer = (ROOT / "submodules/TelegramUI/Sources/Chat/ChatControllerLoadDisplayNode.swift").read_text(encoding="utf-8")
        self.assertIn("spaceGramDelayedMessages(strongSelf.transformEnqueueMessages", composer)
        self.assertIn("var shouldOpenScheduledMessages = false", composer)
        self.assertNotIn("shouldOpenScheduledMessages = delayedMessages.1", composer)
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

    def test_delayed_send_ack_clears_once_without_local_ghost_transition(self):
        node = (ROOT / "submodules/TelegramUI/Sources/ChatControllerNode.swift").read_text(encoding="utf-8")
        controller = (ROOT / "submodules/TelegramUI/Sources/ChatController.swift").read_text(encoding="utf-8")
        loader = (ROOT / "submodules/TelegramUI/Sources/Chat/ChatControllerLoadDisplayNode.swift").read_text(encoding="utf-8")
        self.assertIn("spaceGramDelayedDraftEnqueueInFlight", node)
        self.assertIn("textInputPanelNode.text != sentComposerText", node)
        self.assertIn("spaceGramDelayedMediaEnqueueInFlight", controller)
        self.assertIn("enqueueCompletion?(true)", loader)
        self.assertIn("enqueueCompletion?(false)", loader)
        self.assertIn("if !isAutomaticDelayedSend", node)
        self.assertIn("if automaticDelayedCandidate", controller)
        self.assertIn("skipAddingTransitions = true", controller)
        self.assertIn("if !isSpaceGramDelayedSend", loader)

    def test_push_registration_and_entitlement_contract(self):
        delegate = (ROOT / "submodules/TelegramUI/Sources/AppDelegate.swift").read_text(encoding="utf-8")
        accounts = (ROOT / "submodules/TelegramUI/Sources/SharedAccountContext.swift").read_text(encoding="utf-8")
        build = (ROOT / "Telegram/BUILD").read_text(encoding="utf-8")
        workflow = (ROOT / ".github/workflows/spacegram-ios-test.yml").read_text(encoding="utf-8")
        build_notes = (ROOT / "SpaceGram/IOS_TEST_BUILD.md").read_text(encoding="utf-8")
        for token in ("requestAuthorization", "registerForRemoteNotifications", "didRegisterForRemoteNotificationsWithDeviceToken", "notificationTokenPromise.set"):
            self.assertIn(token, delegate)
        self.assertIn("self.activeAccountContexts", accounts)
        self.assertIn("registerNotificationToken", accounts)
        self.assertIn("unregisterNotificationToken", accounts)
        self.assertIn("otherAccountUserIds", accounts)
        self.assertIn("<key>aps-environment</key>", build)
        self.assertIn("group.{telegram_bundle_id}", build)
        self.assertIn(":NotificationContentExtension", build)
        self.assertIn(":NotificationServiceExtension", build)
        self.assertIn("build --//Telegram:disableExtensions", workflow)
        self.assertIn("intermediate artifact for re-signing", build_notes)
        self.assertIn("APNs", build_notes)

    def test_ghost_presence_and_activity_send_boundaries(self):
        presence = (ROOT / "submodules/TelegramCore/Sources/State/ManagedAccountPresence.swift").read_text(encoding="utf-8")
        self.assertIn("return (value.0 && !value.1, value.2)", presence)
        self.assertIn("let presenceInputs: Signal<(Bool, Bool, Bool), NoError>", presence)
        self.assertIn("self.onlineTimer?.invalidate()", presence)
        self.assertEqual(presence.count("Api.functions.account.updateStatus"), 2)

        activity = (ROOT / "submodules/TelegramCore/Sources/State/ManagedLocalInputActivities.swift").read_text(encoding="utf-8")
        self.assertIn("combineLatest(activities, spaceGramSuppressChatActivitySignal())", activity)
        self.assertIn("if SpaceGramGhostPolicy.suppressChatActivity", activity)
        self.assertIn("if !isSpeakingInGroupCall(activity)", activity)

    def test_ghost_restores_local_scroll_and_self_profile_label(self):
        history = (ROOT / "submodules/TelegramUI/Sources/ChatHistoryViewForLocation.swift").read_text(encoding="utf-8")
        navigation = (ROOT / "submodules/TelegramUI/Sources/NavigateToChatController.swift").read_text(encoding="utf-8")
        header = (ROOT / "submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoHeaderNode.swift").read_text(encoding="utf-8")
        self.assertIn("SpaceGramGhostPolicy.suppressAutomaticReads", history)
        self.assertLess(history.index("SpaceGramGhostPolicy.suppressAutomaticReads"), history.index("else if let maxReadIndex"))
        self.assertNotIn("SpaceGramGhostPolicy", navigation)
        self.assertIn("SpaceGramGhostPolicy.suppressOnlinePresence", header)
        self.assertIn('ngI18n("SpaceGram.Hub.Ghost"', header)

    def test_deleted_messages_use_presentation_only_overlay(self):
        overlay = (ROOT / "SpaceGram/HistoryOverlay/SpaceGramDeletedMessageOverlay.swift").read_text(encoding="utf-8")
        entries = (ROOT / "submodules/TelegramUI/Sources/ChatHistoryEntriesForView.swift").read_text(encoding="utf-8")
        node = (ROOT / "submodules/TelegramUI/Sources/ChatHistoryListNode.swift").read_text(encoding="utf-8")

        self.assertIn("PostboxViewKey.orderedItemList", overlay)
        self.assertIn("SpaceGramHistoryPresentationModel.deletedSnapshot", overlay)
        self.assertIn("namespace: Namespaces.Message.Local", overlay)
        self.assertIn("SpaceGramDeletedMessageAttribute", overlay)
        self.assertNotIn("transaction.addMessages", overlay)
        self.assertNotIn("transaction.updateMessage", overlay)
        self.assertIn("!liveMessageIds.contains(item.originalMessageId)", entries)
        self.assertIn("entries.append(.MessageEntry(message, presentationData, true", entries)
        self.assertIn("entries.sort()", entries)
        self.assertIn("SpaceGramSettings.shared.captureDeletedMessages ? items : []", node)

    def test_deleted_media_and_marker_defaults_are_visible(self):
        settings = (ROOT / "SpaceGram/Settings/SpaceGramSettings.swift").read_text(encoding="utf-8")
        status = (ROOT / "submodules/TelegramUI/Components/Chat/ChatMessageDateAndStatusNode/Sources/StringForMessageTimestampStatus.swift").read_text(encoding="utf-8")
        russian = (ROOT / "SpaceGram/Strings/Strings/ru.lproj/SpaceGramLocalizable.strings").read_text(encoding="utf-8")
        self.assertIn('@SpaceGramDefault("spacegram.settings.mediaArchiveEnabled", true)', settings)
        self.assertIn('"\\u{1F5D1}\\u{FE0E} "', status)
        self.assertIn('"SpaceGram.History.Deleted" = "Удалено";', russian)

    def test_edit_history_is_user_facing_and_read_only(self):
        menu = (ROOT / "submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift").read_text(encoding="utf-8")
        self.assertIn("SpaceGramHistoryStore.load", menu)
        self.assertIn('ngI18n("SpaceGram.History.EditHistory"', menu)
        self.assertIn('ngI18n("SpaceGram.History.Previous"', menu)
        self.assertIn('ngI18n("SpaceGram.History.Current"', menu)
        self.assertIn("historyRecord.revisions.sorted", menu)
        self.assertNotIn("SpaceGramHistoryStore.upsert", menu)

    def test_ghost_quick_button_uses_the_persisted_master(self):
        settings = (ROOT / "SpaceGram/Settings/SpaceGramSettings.swift").read_text(encoding="utf-8")
        chat_list = (ROOT / "submodules/ChatListUI/Sources/ChatListController.swift").read_text(encoding="utf-8")
        delayed = (ROOT / "submodules/TelegramUI/Sources/ChatController.swift").read_text(encoding="utf-8")
        self.assertIn('@SpaceGramDefault("spacegram.settings.ghostModeEnabled", false)', settings)
        self.assertIn("ghostModeEnabled = enabled", settings)
        self.assertIn("SpaceGramSettings.shared.ghostMode.enabled", chat_list)
        self.assertNotIn("SpaceGramSettings.shared.ghostMode.isFull", chat_list)
        self.assertIn("guard settings.ghostMode.enabled, settings.delayedSend", delayed)

    def test_message_shot_and_custom_menu_are_bounded_and_opt_in(self):
        renderer = (ROOT / "SpaceGram/MessageShot/SpaceGramMessageShotRenderer.swift").read_text(encoding="utf-8")
        registry = (ROOT / "SpaceGram/Settings/SpaceGramMessageAction.swift").read_text(encoding="utf-8")
        menu = (ROOT / "submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift").read_text(encoding="utf-8")
        settings = (ROOT / "SpaceGram/SettingsUI/SpaceGramMessageMenuSettingsController.swift").read_text(encoding="utf-8")

        self.assertIn("maximumMessages: Int = 50", renderer)
        self.assertIn("maximumHeight: CGFloat = 8192.0", renderer)
        self.assertIn("maximumPixelCount: CGFloat = 20_000_000.0", renderer)
        self.assertNotIn("drawHierarchy", renderer)
        self.assertIn("UIGraphicsImageRenderer", renderer)

        self.assertIn("public enum SpaceGramMessageAction", registry)
        self.assertIn("object(forKey: action.preferenceKey) != nil", registry)
        self.assertIn("case .forwardAsNew:\n            return false", registry)
        legacy_registry = (ROOT / "SpaceGram/Enhancements/Settings/NagramMessageMenuSettings.swift").read_text(encoding="utf-8")
        for custom_id in (".saveStickerToCameraRoll", ".repeat", ".repeatWithoutQuote", ".saveToSavedMessages", ".forwardWithoutQuote", ".viewAuthorMessages", ".selectFromAuthor"):
            self.assertIn(custom_id, legacy_registry[legacy_registry.index("nagramDefaultDisabledMessageMenuItemIds"):])
        self.assertIn("action.isApplicable(to: spaceGramActionContext)", menu)
        self.assertIn("SpaceGramMessageShotRenderer().render", menu)
        self.assertNotIn("Qwen", settings)

        for native_id in (".reply", ".copy", ".edit", ".pin", ".forward", ".select", ".delete"):
            self.assertIn(f"actions.append({native_id}", menu)
        for forbidden in ("SpaceGram AI", "Qwen", "Assistant"):
            self.assertNotIn(forbidden, menu)

    def test_outgoing_translation_is_opt_in_and_preserves_draft_on_failure(self):
        defaults = (ROOT / "SpaceGram/Enhancements/Settings/NagramSettings.swift").read_text(encoding="utf-8")
        send_options = (ROOT / "submodules/TelegramUI/Sources/Chat/ChatMessageDisplaySendMessageOptions.swift").read_text(encoding="utf-8")
        self.assertIn('@NagramDefault("nagram.translateBeforeSend", false)', defaults)
        self.assertIn("if NagramSettings.shared.translateBeforeSend", send_options)
        self.assertIn("!translatedText.trimmingCharacters", send_options)
        self.assertIn("presentTranslationFailed(selfController)", send_options)
        update = send_options.index("withUpdatedEffectiveInputState")
        translation_result = send_options.index("guard let (translatedText, translatedEntities) = result")
        self.assertGreater(update, translation_result, "the draft must change only after a non-empty translation")

    def test_protected_media_action_requires_local_resource_and_supports_files(self):
        menu = (ROOT / "submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift").read_text(encoding="utf-8")
        controller = (ROOT / "submodules/TelegramUI/Sources/ChatController.swift").read_text(encoding="utf-8")
        exporter = (ROOT / "submodules/TelegramUI/Sources/SaveMediaToFiles.swift").read_text(encoding="utf-8")
        self.assertIn("resourceAvailable && serverCopyProtected", menu)
        self.assertIn("!message.containsSecretMedia", menu)
        self.assertIn("case .files", menu)
        self.assertIn("controllerInteraction.saveMediaToFiles(message.id)", menu)
        self.assertIn("if let mediaFile = media as? TelegramMediaFile", controller)
        self.assertIn("UTType(mimeType:", exporter)


if __name__ == "__main__":
    unittest.main()
