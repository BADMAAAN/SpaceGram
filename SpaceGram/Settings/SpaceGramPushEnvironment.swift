import Foundation

public enum SpaceGramPushEnvironment {
    // The installed profile is replaced by the signer. DEBUG describes compiler
    // optimizations, not the APNs endpoint that issued this device's token.
    public static let currentSandbox: Bool? = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision") else {
            return false // App Store distributions have no embedded profile.
        }
        guard let data = try? Data(contentsOf: url), let sandbox = sandbox(profileData: data) else {
            NSLog("SpaceGramPush: installed profile has no readable aps-environment; check the final signing capabilities")
            return nil
        }
        return sandbox
    }()

    public static func sandbox(profileData: Data) -> Bool? {
        guard let start = profileData.range(of: Data("<?xml".utf8)),
              let end = profileData.range(of: Data("</plist>".utf8), in: start.lowerBound ..< profileData.endIndex),
              let plist = try? PropertyListSerialization.propertyList(from: profileData.subdata(in: start.lowerBound ..< end.upperBound), format: nil),
              let dictionary = plist as? [String: Any],
              let entitlements = dictionary["Entitlements"] as? [String: Any],
              let environment = entitlements["aps-environment"] as? String else { return nil }
        switch environment {
        case "development": return true
        case "production": return false
        default: return nil
        }
    }
}
