load("@io_bazel_skydoc//stardoc:stardoc.bzl", "stardoc")
load("@bazel_skylib//:bzl_library.bzl", "bzl_library")

exports_files(["defs.bzl", "coursier.bzl"])

licenses(["notice"]) # Apache 2.0

java_binary(
    name = "gmaven_to_bazel",
    srcs = ["java/com/google/gmaven/GMavenToBazel.java"],
    main_class = "com.google.gmaven.GMavenToBazel",
)

stardoc(
    name = "defs_doc",
    input = "defs.bzl",
    out = "defs_doc.md",
    deps = ["//:implementation"],
    symbol_names = ["maven_install"]
)

bzl_library(
    name = "implementation",
    srcs = [
        ":specs.bzl",
        ":defs.bzl",
        ":coursier.bzl",
        "//third_party/bazel_json/lib:json_parser.bzl"
    ],
)
