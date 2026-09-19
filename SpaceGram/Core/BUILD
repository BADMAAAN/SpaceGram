load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "SpaceGramCore",
    module_name = "SpaceGramCore",
    srcs = glob([
        "**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    visibility = [
        "//visibility:public",
    ],
)
