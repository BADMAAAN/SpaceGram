load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "SpaceGramQR",
    module_name = "SpaceGramQR",
    srcs = glob(["*.swift"]),
    copts = ["-warnings-as-errors"],
    sdk_frameworks = [
        "CoreImage",
        "UIKit",
    ],
    visibility = ["//visibility:public"],
)
