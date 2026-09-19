load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "SpaceGramAppearance",
    module_name = "SpaceGramAppearance",
    srcs = glob(["*.swift"]),
    copts = ["-warnings-as-errors"],
    deps = [
        "//submodules/ItemListUI:ItemListUI",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
    ],
    visibility = ["//visibility:public"],
)
