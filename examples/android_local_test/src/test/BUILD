load("@rules_jvm_external//:defs.bzl", "artifact")

android_local_test(
    name = "main_activity_test",
    srcs = ["java/com/example/bazel/MainActivityTest.java"],
    manifest = "AndroidManifest.xml",
    test_class = "com.example.bazel.MainActivityTest",
    deps = [
        "//bazel/robolectric",
        "//src/main:my_lib",
        "@maven//:com_google_guava_guava",
        "@maven//:org_robolectric_annotations",
        "@maven//:org_robolectric_shadows_framework",
        "@maven//:org_assertj_assertj_core",
    ],
)
