load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "SpaceGramPrivacy",
    module_name = "SpaceGramPrivacy",
    deps = ["//SpaceGram/Settings:SpaceGramSettings"],
    srcs = glob(["*.swift"]),
    copts = ["-warnings-as-errors"],
    visibility = ["//visibility:public"],
)
