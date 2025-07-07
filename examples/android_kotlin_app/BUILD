load("@rules_android//rules:rules.bzl", "android_binary")

android_binary(
    name = "app",
    custom_package = "com.example.bazel",
    manifest = "AndroidManifest.xml",
    deps = [
        "//src:lib",
    ],
)
