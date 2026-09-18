load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "TelegramCore",
    module_name = "TelegramCore",
    srcs = glob([
        "Sources/**/*.swift",
    ]) + [
        # // MARK: NAGRAM
        "//Qwengram/HistoryIntegration:Sources",
    ],
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        # // MARK: NAGRAM
        "//Qwengram/HistoryStorage:QwengramHistoryStorage",
        # // MARK: NAGRAM — independent Qwengram media storage.
        "//Qwengram/MediaArchive:QwengramMediaArchive",
        "//Qwengram/Settings:QwengramSettings",
        # // MARK: NAGRAM — reactive Qwengram presence policy.
        "//Qwengram/SettingsSignal:QwengramSettingsSignal",
        "//submodules/TelegramApi:TelegramApi",
        "//submodules/MtProtoKit:MtProtoKit",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/Postbox:Postbox",
        "//submodules/CloudData:CloudData",
        "//submodules/EncryptionProvider:EncryptionProvider",
        "//submodules/CryptoUtils:CryptoUtils",
        "//submodules/NetworkLogging:NetworkLogging",
        "//submodules/Reachability:Reachability",
        "//submodules/ManagedFile:ManagedFile",
        "//submodules/Utils/RangeSet:RangeSet",
        "//submodules/Utils/DarwinDirStat",
        "//submodules/Emoji",
        "//submodules/TelegramCore/FlatBuffers",
        "//submodules/TelegramCore/FlatSerialization",
        "//submodules/MurMurHash32",
        # MARK: NAGRAM
        "//Qwengram/Enhancements/Settings:NagramSettings",
    ],
    visibility = [
        "//visibility:public",
    ],
)
