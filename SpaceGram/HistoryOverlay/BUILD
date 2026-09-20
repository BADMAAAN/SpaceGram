load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "SpaceGramHistoryOverlay",
    module_name = "SpaceGramHistoryOverlay",
    srcs = glob(["*.swift"]),
    copts = ["-warnings-as-errors"],
    deps = [
        "//SpaceGram/HistoryStorage:SpaceGramHistoryStorage",
        "//SpaceGram/MediaArchive:SpaceGramMediaArchive",
        "//submodules/Postbox:Postbox",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/TelegramCore:TelegramCore",
    ],
    visibility = ["//visibility:public"],
)
