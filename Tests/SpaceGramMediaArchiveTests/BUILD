load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("@build_bazel_rules_apple//apple:ios.bzl", "ios_unit_test")
load("@build_bazel_rules_apple//apple/testing/default_runner:ios_test_runner.bzl", "ios_test_runner")

swift_library(
    name = "SpaceGramMediaArchiveTestsLib",
    testonly = True,
    srcs = glob(["*.swift"]),
    deps = [
        "//SpaceGram/AI:SpaceGramAI",
        "//SpaceGram/Enhancements/Settings:NagramSettings",
        "//SpaceGram/HistoryStorage:SpaceGramHistoryStorage",
        "//SpaceGram/MediaArchive:SpaceGramMediaArchive",
        "//SpaceGram/Migration:SpaceGramMigration",
        "//SpaceGram/Privacy:SpaceGramPrivacy",
        "//SpaceGram/Settings:SpaceGramSettings",
        "//SpaceGram/SettingsSignal:SpaceGramSettingsSignal",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
    ],
)

ios_test_runner(
    name = "Runner",
    device_type = "iPhone 17",
    os_version = "26.2",
)

ios_unit_test(
    name = "SpaceGramMediaArchiveTests",
    minimum_os_version = "17.0",
    runner = ":Runner",
    deps = [":SpaceGramMediaArchiveTestsLib"],
    visibility = ["//visibility:public"],
)
