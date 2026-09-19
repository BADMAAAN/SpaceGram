load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "TelegramCore",
    module_name = "TelegramCore",
    srcs = glob([
        "Sources/**/*.swift",
    ]) + [
        # // MARK: NAGRAM
        "//SpaceGram/HistoryIntegration:Sources",
    ],
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        # // MARK: NAGRAM
        "//SpaceGram/HistoryStorage:SpaceGramHistoryStorage",
        # // MARK: NAGRAM — independent SpaceGram media storage.
        "//SpaceGram/MediaArchive:SpaceGramMediaArchive",
        "//SpaceGram/Settings:SpaceGramSettings",
        # // MARK: NAGRAM — reactive SpaceGram presence policy.
        "//SpaceGram/SettingsSignal:SpaceGramSettingsSignal",
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
        "//SpaceGram/Enhancements/Settings:NagramSettings",
    ],
    visibility = [
        "//visibility:public",
    ],
)
