load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "SpaceGramAI",
    module_name = "SpaceGramAI",
    srcs = glob(["**/*.swift"]),
    copts = ["-warnings-as-errors"],
    deps = [
        "//SpaceGram/Migration:SpaceGramMigration",
        "//SpaceGram/Settings:SpaceGramSettings",
    ],
    visibility = ["//visibility:public"],
)
