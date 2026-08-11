load("@io_bazel_stardoc//stardoc:stardoc.bzl", "stardoc")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

exports_files(
    [
        "includes/main_functions_header.md",
    ],
    visibility = ["//scripts:__pkg__"],
)

stardoc(
    name = "defs",
    out = "defs.md",
    input = "//:defs.bzl",
    symbol_names = [
        "javadoc",
        "java_export",
        "maven_bom",
    ],
    visibility = ["//scripts:__pkg__"],
    deps = [
        "//:implementation",
        "@bazel_skylib//lib:structs",
        "@bazel_skylib//rules:run_binary",
        "@rules_java//java/private:proto_support",
    ],
)

stardoc(
    name = "bzlmod",
    out = "bzlmod.md",
    input = "//:extensions.bzl",
    visibility = ["//scripts:__pkg__"],
    deps = [
        "//:implementation",
    ],
)

sh_binary(
    name = "update",
    srcs = ["update_docs.sh"],
    args = [
        "$(location //scripts:generate_api_reference)",
        "api.md",
        "$(location :bzlmod)",
        "bzlmod-api.md",
    ],
    data = [
        ":bzlmod",
        "//scripts:generate_api_reference",
    ],
)

sh_test(
    name = "generated_docs_test",
    size = "small",
    srcs = ["check_generated_docs.sh"],
    args = [
        "api.md",
        "$(location :api.md)",
        "$(location //scripts:generate_api_reference)",
        "bzlmod-api.md",
        "$(location :bzlmod-api.md)",
        "$(location :bzlmod)",
    ],
    data = [
        ":api.md",
        ":bzlmod",
        ":bzlmod-api.md",
        "//scripts:generate_api_reference",
    ],
)
