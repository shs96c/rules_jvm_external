load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_file")
load("//private:versions.bzl", "COURSIER_CLI_GITHUB_ASSET_URL", "COURSIER_CLI_SHA256")

def _non_bzlmod_deps_impl(mctx):
    http_file(
        name = "coursier_cli",
        sha256 = COURSIER_CLI_SHA256,
        urls = [COURSIER_CLI_GITHUB_ASSET_URL],
    )

    http_file(
        name = "buildifier-linux-arm64",
        sha256 = "917d599dbb040e63ae7a7e1adb710d2057811902fdc9e35cce925ebfd966eeb8",
        urls = ["https://github.com/bazelbuild/buildtools/releases/download/5.1.0/buildifier-linux-arm64"],
    )

    http_file(
        name = "buildifier-linux-x86_64",
        sha256 = "52bf6b102cb4f88464e197caac06d69793fa2b05f5ad50a7e7bf6fbd656648a3",
        urls = ["https://github.com/bazelbuild/buildtools/releases/download/5.1.0/buildifier-linux-amd64"],
    )

    http_file(
        name = "buildifier-macos-arm64",
        sha256 = "745feb5ea96cb6ff39a76b2821c57591fd70b528325562486d47b5d08900e2e4",
        urls = ["https://github.com/bazelbuild/buildtools/releases/download/5.1.0/buildifier-darwin-arm64"],
    )

    http_file(
        name = "buildifier-macos-x86_64",
        sha256 = "c9378d9f4293fc38ec54a08fbc74e7a9d28914dae6891334401e59f38f6e65dc",
        urls = ["https://github.com/bazelbuild/buildtools/releases/download/5.1.0/buildifier-darwin-amd64"],
    )

    http_file(
        name = "hamcrest_core_for_test",
        downloaded_file_path = "hamcrest-core-1.3.jar",
        sha256 = "66fdef91e9739348df7a096aa384a5685f4e875584cce89386a7a47251c4d8e9",
        urls = [
            "https://repo1.maven.org/maven2/org/hamcrest/hamcrest-core/1.3/hamcrest-core-1.3.jar",
        ],
    )

    http_file(
        name = "hamcrest_core_srcs_for_test",
        downloaded_file_path = "hamcrest-core-1.3-sources.jar",
        sha256 = "e223d2d8fbafd66057a8848cc94222d63c3cedd652cc48eddc0ab5c39c0f84df",
        urls = [
            "https://repo1.maven.org/maven2/org/hamcrest/hamcrest-core/1.3/hamcrest-core-1.3-sources.jar",
        ],
    )

    http_file(
        name = "gson_for_test",
        downloaded_file_path = "gson-2.9.0.jar",
        sha256 = "c96d60551331a196dac54b745aa642cd078ef89b6f267146b705f2c2cbef052d",
        urls = [
            "https://repo1.maven.org/maven2/com/google/code/gson/gson/2.9.0/gson-2.9.0.jar",
        ],
    )

    http_file(
        name = "junit_platform_commons_for_test",
        downloaded_file_path = "junit-platform-commons-1.8.2.jar",
        sha256 = "d2e015fca7130e79af2f4608dc54415e4b10b592d77333decb4b1a274c185050",
        urls = [
            "https://repo1.maven.org/maven2/org/junit/platform/junit-platform-commons/1.8.2/junit-platform-commons-1.8.2.jar",
        ],
    )

    # https://github.com/bazelbuild/rules_jvm_external/issues/865
    http_file(
        name = "google_api_services_compute_javadoc_for_test",
        downloaded_file_path = "google-api-services-compute-v1-rev235-1.25.0-javadoc.jar",
        sha256 = "b03be5ee8effba3bfbaae53891a9c01d70e2e3bd82ad8889d78e641b22bd76c2",
        urls = [
            "https://repo1.maven.org/maven2/com/google/apis/google-api-services-compute/v1-rev235-1.25.0/google-api-services-compute-v1-rev235-1.25.0-javadoc.jar",
        ],
    )

non_bzlmod_deps = module_extension(
    _non_bzlmod_deps_impl,
)
