load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_file")
load("//private:coursier_utilities.bzl", "strip_packaging_and_classifier_and_version")

def escape(string):
    coordinates = strip_packaging_and_classifier_and_version(string)

    for char in [".", "-", ":", "/", "+"]:
        coordinates = coordinates.replace(char, "_")
    return coordinates.replace("[", "").replace("]", "").split(",")[0]

def download_pinned_deps(artifacts, http_files):
    seen_repo_names = []

    for artifact in artifacts:
        http_file_repository_name = escape(artifact["coordinates"])

        if http_file_repository_name in http_files:
            continue

        urls = artifact["urls"]
        if len(urls) == 0 or [None] == urls:
            continue

        seen_repo_names.append(http_file_repository_name)
        http_files.append(http_file_repository_name)

        print(artifact["coordinates"], " -> ", http_file_repository_name)
        http_file(
            name = http_file_repository_name,
            sha256 = artifact["sha256"],
            urls = artifact["urls"],
            downloaded_file_path = artifact["file"],
        )

    return seen_repo_names
