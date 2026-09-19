load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "SpaceGramHistoryUI",
    module_name = "SpaceGramHistoryUI",
    srcs = glob(["*.swift"]),
    copts = ["-warnings-as-errors"],
    deps = [
        "//SpaceGram/Appearance:SpaceGramAppearance",
        "//SpaceGram/Strings:SpaceGramStrings",
        "//SpaceGram/MediaArchive:SpaceGramMediaArchive",
        "//SpaceGram/HistoryStorage:SpaceGramHistoryStorage",
        "//submodules/AccountContext:AccountContext",
        "//submodules/Display:Display",
        "//submodules/ItemListUI:ItemListUI",
        "//submodules/LocalizedPeerData:LocalizedPeerData",
        "//submodules/Postbox:Postbox",
        "//submodules/PresentationDataUtils:PresentationDataUtils",
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/TextFormat:TextFormat",
    ],
    visibility = [
        "//SpaceGram/SettingsUI:__pkg__",
        "//submodules/TelegramUI:__pkg__",
    ],
)
