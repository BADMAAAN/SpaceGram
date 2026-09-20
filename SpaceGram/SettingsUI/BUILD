load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "SpaceGramSettingsUI",
    module_name = "SpaceGramSettingsUI",
    srcs = glob([
        "**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//SpaceGram/Enhancements/Settings:NagramSettings",
        "//SpaceGram/Enhancements/SettingsUI:NagramSettingsUI",
        "//SpaceGram/Appearance:SpaceGramAppearance",
        "//SpaceGram/Strings:SpaceGramStrings",
        "//SpaceGram/Bots:SpaceGramBots",
        "//SpaceGram/HistoryStorage:SpaceGramHistoryStorage",
        "//SpaceGram/MediaArchive:SpaceGramMediaArchive",
        "//SpaceGram/Privacy:SpaceGramPrivacy",
        "//SpaceGram/QR:SpaceGramQR",
        "//SpaceGram/Settings:SpaceGramSettings",
        "//SpaceGram/SettingsSignal:SpaceGramSettingsSignal",
        "//SpaceGram/Enhancements/Translate:NagramTranslate",
        "//submodules/AsyncDisplayKit",
        "//submodules/AccountContext:AccountContext",
        "//submodules/Display:Display",
        "//submodules/ItemListUI:ItemListUI",
        "//submodules/LocalAuth:LocalAuth",
        "//submodules/PresentationDataUtils:PresentationDataUtils",
        "//submodules/Postbox:Postbox",
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/TextFormat:TextFormat",
        "//submodules/SettingsUI:SettingsUI",
    ],
    visibility = [
        "//visibility:public",
    ],
)
