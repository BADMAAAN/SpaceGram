load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "QwengramAI",
    module_name = "QwengramAI",
    srcs = glob(["**/*.swift"]),
    copts = ["-warnings-as-errors"],
    deps = ["//Qwengram/Settings:QwengramSettings"],
    visibility = ["//visibility:public"],
)
