load("//private:dependency_tree_parser.bzl", "JETIFY_INCLUDE_LIST_JETIFY_ALL", "parser")

_BUILD = """
# package(default_visibility = [{visibilities}])  # https://github.com/bazelbuild/bazel/issues/13681

load("@rules_jvm_external//private/rules:jvm_import.bzl", "jvm_import")
load("@rules_jvm_external//private/rules:jetifier.bzl", "jetify_aar_import", "jetify_jvm_import")

{imports}
"""

def _generate_pinned_repo_impl(rctx):
    lock_file = json.decode(rctx.read(rctx.path(rctx.attr.lock_file)))
    dep_tree = lock_file["dependency_tree"]

    artifacts = [json.decode(a) for a in rctx.attr.artifacts]

    for artifact in artifacts:
        (generated_imports, jar_versionless_target_labels) = parser.generate_imports(
            repository_ctx = rctx,
            dep_tree = dep_tree,
            explicit_artifacts = {
                a["groupId"] + ":" + a["artifactId"] + (":" + a["classifier"] if "classifier" in a else ""): True
                for a in artifacts
            },
            neverlink_artifacts = {
                a["group"] + ":" + a["artifact"] + (":" + a["classifier"] if "classifier" in a else ""): True
                for a in artifacts
                if a.get("neverlink", False)
            },
            testonly_artifacts = {
                a["group"] + ":" + a["artifact"] + (":" + a["classifier"] if "classifier" in a else ""): True
                for a in artifacts
                if a.get("testonly", False)
            },
            override_targets = [],
            skip_maven_local_dependencies = False,
        )

        rctx.file(
            "BUILD.bazel",
            _BUILD.format(
                visibilities = ",".join(["\"%s\"" % s for s in (["//visibility:public"])]),
                repository_name = rctx.name,
                imports = generated_imports,
            ),
            executable = False,
        )

generate_pinned_repo = repository_rule(
    _generate_pinned_repo_impl,
    attrs = {
        "artifacts": attr.string_list(),
        "fetch_javadoc": attr.bool(default = False),
        "fetch_sources": attr.bool(default = False),
        "jetify": attr.bool(default = False),
        "jetify_include_list": attr.string_list(default = JETIFY_INCLUDE_LIST_JETIFY_ALL),
        "lock_file": attr.label(),
        "maven_install_json": attr.label(allow_single_file = True),
        "strict_visibility": attr.bool(default = True),
        "strict_visibility_value": attr.string_list(default = ["//visibility:private"]),
    },
)
