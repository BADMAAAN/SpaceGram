load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "QwengramSettingsUI",
    module_name = "QwengramSettingsUI",
    srcs = glob([
        "**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//Qwengram/Strings:QwengramStrings",
        "//Qwengram/AI:QwengramAI",
        "//Qwengram/Bots:QwengramBots",
        "//Qwengram/HistoryUI:QwengramHistoryUI",
        "//Qwengram/Settings:QwengramSettings",
        "//Qwengram/SettingsSignal:QwengramSettingsSignal",
        "//submodules/AsyncDisplayKit",
        "//submodules/AccountContext:AccountContext",
        "//submodules/Display:Display",
        "//submodules/ItemListUI:ItemListUI",
        "//submodules/PresentationDataUtils:PresentationDataUtils",
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
    ],
    visibility = [
        "//visibility:public",
    ],
)
