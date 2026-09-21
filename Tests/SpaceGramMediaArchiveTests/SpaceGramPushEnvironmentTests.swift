import Foundation
import SpaceGramSettings
import XCTest

final class SpaceGramPushEnvironmentTests: XCTestCase {
    private func profile(_ environment: String?) throws -> Data {
        var entitlements: [String: Any] = [:]
        entitlements["aps-environment"] = environment
        let plist = try PropertyListSerialization.data(fromPropertyList: ["Entitlements": entitlements], format: .xml, options: 0)
        return Data([0x30, 0x82]) + plist + Data([0, 0xff])
    }

    func testInstalledProfileSelectsEndpointIndependentlyOfDebugBuild() throws {
        XCTAssertEqual(SpaceGramPushEnvironment.sandbox(profileData: try profile("development")), true)
        XCTAssertEqual(SpaceGramPushEnvironment.sandbox(profileData: try profile("production")), false)
    }

    func testMissingOrMalformedPushCapabilityIsNotGuessed() throws {
        XCTAssertNil(SpaceGramPushEnvironment.sandbox(profileData: try profile(nil)))
        XCTAssertNil(SpaceGramPushEnvironment.sandbox(profileData: try profile("unknown")))
        XCTAssertNil(SpaceGramPushEnvironment.sandbox(profileData: Data("<?xml truncated".utf8)))
    }
}
