load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "TelegramAccountAuxiliaryMethods",
    module_name = "TelegramAccountAuxiliaryMethods",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//SpaceGram/Privacy:SpaceGramPrivacy", # MARK: NAGRAM — outgoing photo metadata policy.
        "//submodules/Display",
        "//submodules/TelegramCore",
        "//submodules/Postbox",
        "//submodules/MediaResources",
        "//submodules/PassportUI",
        "//submodules/OpenInExternalAppUI",
        "//submodules/MusicAlbumArtResources",
        "//submodules/LocalMediaResources",
        "//submodules/LocationResources",
        "//submodules/ChatInterfaceState",
        "//submodules/WallpaperResources",
        "//submodules/AppBundle",
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/ICloudResources",
        "//submodules/TelegramUI/Components/Resources/FetchVideoMediaResource",
        "//submodules/TelegramUI/Components/Resources/FetchAudioMediaResource",
    ],
    visibility = [
        "//visibility:public",
    ],
)
