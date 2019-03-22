load("@rules_jvm_external//:defs.bzl", "artifact")
load("@mabel//rules/maven_deps:maven_deps_workspace_generator.bzl", "deps_workspace_generator_rule", "artifact")
load("//bazel/robolectric/main_deps:dependencies.bzl", main_generate_transitive_dependency_targets = "generate_transitive_dependency_targets")
main_generate_transitive_dependency_targets()

deps_workspace_generator_rule(
    name = 'main_deps',
    maven_deps = [
        artifact("org.robolectric:robolectric:3.8"),
        artifact("org.robolectric:android-all:5.0.2_r3-robolectric-r0")
    ],
    generated_targets_prefix = "main_deps___"
)

java_library(
    name = "robolectric",
    data = [":robolectric-deps.properties"],
    exports = [
        "@maven//:androidx_test_ext_junit",
        "//bazel/robolectric/main_deps/org/robolectric/robolectric",
        "//bazel/robolectric/main_deps/org/robolectric/android-all",
        # artifact("org.robolectric:robolectric"),
        # artifact("org.robolectric:android-all"),
    ],
    visibility = ["//src/test:__subpackages__"],
)

filegroup(
    name = "android_all_jars",
    srcs = [
        "//bazel/robolectric/main_deps/org/robolectric/android-all",
    ],
)

genrule(
    name = "gen_properties",
    srcs = [":android_all_jars"],
    outs = ["robolectric-deps.properties"],
    cmd = "$(location :gen_deps) $(locations :android_all_jars) > $@",
    tools = [":gen_deps"],
)

py_binary(
    name = "gen_deps",
    srcs = ["gen_deps.py"],
)
