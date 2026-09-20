import Foundation
import NagramSettings
import SpaceGramMigration
import SpaceGramSettings
import XCTest

final class SpaceGramFeatureDefaultsTests: XCTestCase {
    func testFormattingDefaultDoesNotOverwriteStoredChoice() {
        let defaults = NagramDemoMode.userDefaults
        let key = "nagram.showTextStyleToolbar"
        let original = defaults.object(forKey: key)
        defer {
            if let original { defaults.set(original, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        defaults.removeObject(forKey: key)
        XCTAssertFalse(NagramSettings.shared.showTextStyleToolbar)
        defaults.set(true, forKey: key)
        XCTAssertTrue(NagramSettings.shared.showTextStyleToolbar)
    }

    func testMigrationPreservesPartialGhostAndHistoryChoices() {
        let name = "SpaceGramFeatureDefaultsTests." + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: name) else {
            return XCTFail("Unable to create isolated defaults")
        }
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "qwengram.settings.hideOnlinePresence")
        defaults.set(false, forKey: "qwengram.settings.saveEditedMessages")
        defaults.set(false, forKey: "qwengram.settings.saveServerDeletedMessages")
        defaults.set(false, forKey: "spacegram.settings.hideOnlinePresence")
        XCTAssertTrue(SpaceGramMigrationCoordinator.migrateDefaults(defaults))
        XCTAssertFalse(defaults.bool(forKey: "spacegram.settings.hideOnlinePresence"))
        XCTAssertFalse(defaults.bool(forKey: "spacegram.settings.saveEditedMessages"))
        XCTAssertFalse(defaults.bool(forKey: "spacegram.settings.saveServerDeletedMessages"))
        XCTAssertFalse(defaults.bool(forKey: "spacegram.settings.ghostModeEnabled"))
        XCTAssertNil(defaults.object(forKey: "spacegram.settings.delayedSend"))
        XCTAssertNil(defaults.object(forKey: "spacegram.settings.showGhostButton"))
        XCTAssertTrue(SpaceGramMigrationCoordinator.migrateDefaults(defaults))
        XCTAssertFalse(defaults.bool(forKey: "spacegram.settings.saveEditedMessages"))
    }

    func testCustomMessageActionsDefaultOffAndPersist() {
        let action = SpaceGramMessageAction.messageShot
        let key = "spacegram.settings.messageAction.messageShot"
        let original = UserDefaults.standard.object(forKey: key)
        defer {
            if let original {
                UserDefaults.standard.set(original, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertFalse(SpaceGramSettings.shared.isMessageActionEnabled(action))
        SpaceGramSettings.shared.setMessageActionEnabled(action, enabled: true)
        XCTAssertTrue(SpaceGramSettings.shared.isMessageActionEnabled(action))
    }

    func testCustomMessageActionApplicability() {
        let empty = SpaceGramMessageActionContext(hasMessages: false, hasRenderableContent: false, hasAvailableProtectedMedia: false, canForward: false)
        XCTAssertFalse(SpaceGramMessageAction.messageShot.isApplicable(to: empty))
        XCTAssertFalse(SpaceGramMessageAction.saveProtectedMedia.isApplicable(to: empty))
        XCTAssertFalse(SpaceGramMessageAction.forwardAsNew.isApplicable(to: empty))

        let available = SpaceGramMessageActionContext(hasMessages: true, hasRenderableContent: true, hasAvailableProtectedMedia: true, canForward: true)
        XCTAssertTrue(SpaceGramMessageAction.messageShot.isApplicable(to: available))
        XCTAssertTrue(SpaceGramMessageAction.saveProtectedMedia.isApplicable(to: available))
        XCTAssertTrue(SpaceGramMessageAction.forwardWithoutName.isApplicable(to: available))
        XCTAssertFalse(SpaceGramMessageAction.forwardAsNew.isApplicable(to: available))
    }
}
