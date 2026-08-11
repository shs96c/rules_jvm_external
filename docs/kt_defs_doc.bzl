# This documentation-only mirror exists because rules_kotlin 2.2.2 does not
# declare the private plugin bzl_library dependencies loaded by its public JVM
# API. That metadata gap prevents Stardoc from reading //:kt_defs.bzl and the
# real //private/rules:kt_jvm_export.bzl definition directly.
#
# Keep the signature and docstring below verbatim with the real definition. The
# generated-doc drift test checks generated output only. It does not detect
# mirror-versus-source drift, so code review remains the guard against that
# residual risk.
#
# TODO: Replace this mirror with a direct //:kt_defs.bzl Stardoc input when
# rules_kotlin exposes complete bzl_library metadata for its JVM API.

DEFAULT_EXCLUDED_WORKSPACES = [
    "com_google_protobuf",
    "protobuf",
]

def kt_jvm_export(
        name,
        maven_coordinates,
        deploy_env = [],
        excluded_workspaces = {name: None for name in DEFAULT_EXCLUDED_WORKSPACES},
        pom_template = None,
        visibility = None,
        tags = [],
        testonly = None,
        **kwargs):
    """Extends `kt_jvm_library` to allow maven artifacts to be uploaded.

    This rule is the Kotlin JVM version of `java_export`.

    This macro can be used as a drop-in replacement for `kt_jvm_library`, but
    also generates an implicit `name.publish` target that can be run to publish
    maven artifacts derived from this macro to a maven repository. The publish
    rule understands the following variables (declared using `--define` when
    using `bazel run`):

      * `maven_repo`: A URL for the repo to use. May be "https" or "file".
      * `maven_user`: The user name to use when uploading to the maven repository.
      * `maven_password`: The password to use when uploading to the maven repository.

    This macro also generates a `name-pom` target that creates the `pom.xml` file
    associated with the artifacts. The template used is derived from the (optional)
    `pom_template` argument, and the following substitutions are performed on
    the template file:

      * `{groupId}`: Replaced with the maven coordinates group ID.
      * `{artifactId}`: Replaced with the maven coordinates artifact ID.
      * `{version}`: Replaced by the maven coordinates version.
      * `{type}`: Replaced by the maven coordinates type, if present (defaults to "jar")
      * `{dependencies}`: Replaced by a list of maven dependencies directly relied upon
        by kt_jvm_library targets within the artifact.

    The "edges" of the artifact are found by scanning targets that contribute to
    runtime dependencies for the following tags:

      * `maven_coordinates=group:artifact:type:version`: Specifies a dependency of
        this artifact.
      * `maven:compile-only`: Specifies that this dependency should not be listed
        as a dependency of the artifact being generated.

    To skip generation of the javadoc jar, add the `no-javadocs` tag to the target.

    Generated rules:
      * `name`: A `kt_jvm_library` that other rules can depend upon.
      * `name-docs`: A javadoc jar file.
      * `name-pom`: The pom.xml file.
      * `name.publish`: To be executed by `bazel run` to publish to a maven repo.

    Args:
      name: A unique name for this target.
      maven_coordinates: The maven coordinates for this target.
      deploy_env: A list of labels of Java targets to exclude from the generated JAR.
      excluded_workspaces: Workspace names whose artifacts should not be included in the Maven JAR.
      pom_template: The template to use for the pom.xml file.
      visibility: The visibility of the target.
      tags: Tags applied to the generated targets.
      testonly: Whether the generated targets should be marked test-only.
      kwargs: These are passed to [`kt_jvm_library`](https://bazelbuild.github.io/rules_kotlin/kotlin),
        and so may contain any valid parameter for that rule.
    """

    return None
