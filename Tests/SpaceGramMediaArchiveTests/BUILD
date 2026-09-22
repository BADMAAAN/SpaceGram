load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("@build_bazel_rules_apple//apple:ios.bzl", "ios_unit_test")
load("@build_bazel_rules_apple//apple/testing/default_runner:ios_test_runner.bzl", "ios_test_runner")

swift_library(
    name = "SpaceGramMediaArchiveTestsLib",
    testonly = True,
    srcs = glob(["*.swift"]),
    deps = [
        "//SpaceGram/Enhancements/Settings:NagramSettings",
        "//SpaceGram/Enhancements/SettingsSignal:NagramSettingsSignal",
        "//SpaceGram/Enhancements/MediaMetadata:NagramMediaMetadata",
        "//SpaceGram/HistoryStorage:SpaceGramHistoryStorage",
        "//SpaceGram/HistoryOverlay:SpaceGramHistoryOverlay",
        "//SpaceGram/MediaArchive:SpaceGramMediaArchive",
        "//SpaceGram/MessageShot:SpaceGramMessageShot",
        "//SpaceGram/Migration:SpaceGramMigration",
        "//SpaceGram/Privacy:SpaceGramPrivacy",
        "//SpaceGram/Settings:SpaceGramSettings",
        "//SpaceGram/SettingsUI:SpaceGramSettingsUI",
        "//SpaceGram/SettingsSignal:SpaceGramSettingsSignal",
        "//SpaceGram/Strings:SpaceGramStrings",
        "//submodules/Postbox:Postbox",
        "//submodules/Display:Display",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/TelegramCore:TelegramCore",
    ],
)

ios_test_runner(
    name = "Runner",
    device_type = "iPhone 17",
    os_version = "26.2",
)

ios_unit_test(
    name = "SpaceGramMediaArchiveTests",
    # Match the app deployment target; the runner still uses iOS 26.2.
    minimum_os_version = "15.0",
    runner = ":Runner",
    resources = ["//SpaceGram/Strings:SpaceGramLocalizableStrings"],
    deps = [":SpaceGramMediaArchiveTestsLib"],
    visibility = ["//visibility:public"],
)
