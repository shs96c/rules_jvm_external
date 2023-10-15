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

non_bzlmod_deps = module_extension(
    _non_bzlmod_deps_impl,
)
