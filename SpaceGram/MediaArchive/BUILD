load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "SpaceGramMediaArchive",
    module_name = "SpaceGramMediaArchive",
    deps = ["//SpaceGram/Migration:SpaceGramMigration"],
    srcs = glob(["*.swift"]),
    copts = ["-warnings-as-errors"],
    visibility = ["//visibility:public"],
)
