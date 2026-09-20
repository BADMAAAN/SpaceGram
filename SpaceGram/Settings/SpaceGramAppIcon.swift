import Foundation

public enum SpaceGramAppIcon: String, CaseIterable {
    case `default` = "Default"
    case moon = "Moon"
    case earth = "Earth"
    case mars = "Mars"
    case sun = "Sun"
    case saturn = "Saturn"
    case neptune = "Neptune"

    public var alternateIconName: String? {
        return self == .default ? nil : rawValue
    }
}
