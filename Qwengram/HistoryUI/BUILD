load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "QwengramHistoryUI",
    module_name = "QwengramHistoryUI",
    srcs = glob(["*.swift"]),
    copts = ["-warnings-as-errors"],
    deps = [
        "//Qwengram/Strings:QwengramStrings",
        "//Qwengram/MediaArchive:QwengramMediaArchive",
        "//Qwengram/HistoryStorage:QwengramHistoryStorage",
        "//submodules/AccountContext:AccountContext",
        "//submodules/Display:Display",
        "//submodules/ItemListUI:ItemListUI",
        "//submodules/LocalizedPeerData:LocalizedPeerData",
        "//submodules/Postbox:Postbox",
        "//submodules/PresentationDataUtils:PresentationDataUtils",
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
    ],
    visibility = [
        "//Qwengram/SettingsUI:__pkg__",
        "//submodules/TelegramUI:__pkg__",
    ],
)
