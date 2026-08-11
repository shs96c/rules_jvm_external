"""Support for layering Maven dependencies contributed by bzlmod modules."""

load("@bazel_skylib//lib:new_sets.bzl", "sets")
load("//private/lib:coordinates.bzl", "to_key")
load("//private/rules:maven_version.bzl", "compare_maven_versions")

DEFAULT_NAME = "maven"

def warn_if_multiple_contributing_modules(repo, repo_name, non_root_bazel_dep_to_artifacts):
    known_contributing_modules = repo.get("known_contributing_modules", sets.make())
    contributing_module_names = non_root_bazel_dep_to_artifacts.keys()
    new_contributing_modules = sets.difference(sets.make(contributing_module_names), known_contributing_modules)
    if sets.length(new_contributing_modules) > 0:
        print("The maven repository '%s' has contributions from multiple bzlmod modules, and will be resolved together: %s." % (
                  repo_name,
                  sorted(contributing_module_names),
              ) + "\nSee https://github.com/bazel-contrib/rules_jvm_external/blob/master/docs/bzlmod.md#module-dependency-layering" +
              " for more information. \n" +
              " To suppress this warning review the contributions from the other modules and add the following attribute" +
              " in the root MODULE.bazel file: \n" +
              "maven.install(\n" +
              ("  name = \"{0}\"\n".format(repo_name) if repo_name != DEFAULT_NAME else "") +
              "  known_contributing_modules = {0},\n".format(sorted(contributing_module_names)) +
              "  ...\n" +
              ")")

def deduplicate_non_root_artifacts(bazel_dep_to_non_root_artifacts, return_only_artifacts = False):
    coordinate_to_artifact = {}
    for bazel_dep_name in bazel_dep_to_non_root_artifacts:
        for artifact in bazel_dep_to_non_root_artifacts.get(bazel_dep_name, []):
            if not getattr(artifact, "testonly", False):
                artifact_key = to_key(artifact)

                # prioritize highest version
                if artifact_key in coordinate_to_artifact:
                    _bazel_dep_name, current_artifact = coordinate_to_artifact[artifact_key]
                    if compare_maven_versions(current_artifact.version, artifact.version) == -1:
                        coordinate_to_artifact[artifact_key] = (bazel_dep_name, artifact)
                else:
                    coordinate_to_artifact[artifact_key] = (bazel_dep_name, artifact)

    if return_only_artifacts:
        return [v[1] for v in coordinate_to_artifact.values()]
    else:
        return coordinate_to_artifact

# Each bzlmod module may contribute jars to different rules_jvm_external maven repo namespaces.
# We emit a warning to the user if a module overrides an artifact version in the root maven repo.
#
# This can be typical for the default @maven namespace, if a bzlmod dependency
# wishes to contribute to the users' jars.
def merge_with_root_priority(name, root_artifacts, bazel_dep_to_non_root_artifacts, repin_env_var, rje_verbose_env_var):
    """Deduplicate artifacts, giving priority to root module artifacts with force_version set."""
    non_root_coordinate_to_artifact = deduplicate_non_root_artifacts(bazel_dep_to_non_root_artifacts)

    duplicate_artifact_warning = ""
    filtered_non_root_artifacts = []
    for root_artifact in root_artifacts:
        artifact_key = to_key(root_artifact)
        if artifact_key in non_root_coordinate_to_artifact:
            bazel_dep_name, non_root_artifact = non_root_coordinate_to_artifact.pop(artifact_key)
            if not getattr(root_artifact, "force_version", False):
                # prioritize highest version
                if compare_maven_versions(root_artifact.version, non_root_artifact.version) == -1:
                    filtered_non_root_artifacts.append(non_root_artifact)
                    duplicate_artifact_warning = duplicate_artifact_warning + (
                        "\nWARNING: For dependency '%s:%s' the root @%s repo wants version %s, " % (root_artifact.group, root_artifact.artifact, name, root_artifact.version) +
                        "but got %s from the %s bazel dep. " % (non_root_artifact.version, bazel_dep_name) +
                        "Please update the version in your MODULE.bazel or set `force_version = True`."
                    )

    # Add any remaining non root artifacts that weren't found in the root artifact list
    addtional_artifact_message = ""
    for bazel_dep_name, non_root_artifact in non_root_coordinate_to_artifact.values():
        addtional_artifact_message = addtional_artifact_message + (
            "\nINFO: The @%s repo is getting the additional artifact %s:%s:%s from the %s bazel dep." % (name, non_root_artifact.group, non_root_artifact.artifact, non_root_artifact.version, bazel_dep_name)
        )
        filtered_non_root_artifacts.append(non_root_artifact)

    if repin_env_var:
        if duplicate_artifact_warning != "":
            print(duplicate_artifact_warning)
        if rje_verbose_env_var:
            if addtional_artifact_message != "":
                print(addtional_artifact_message)

    return root_artifacts + filtered_non_root_artifacts

def remove_fields(s):
    """Used for reducing an artifact struct down to only those fields that have values"""
    return {
        k: getattr(s, k)
        for k in dir(s)
        if k != "to_json" and k != "to_proto" and getattr(s, k, None)
    } | {"version": getattr(s, "version", "")}

def _defines_gradle_module_version(candidate, current):
    """Whether candidate should force the Gradle module version instead of current."""
    candidate_classified = bool(getattr(candidate, "classifier", None))
    current_classified = bool(getattr(current, "classifier", None))
    if candidate_classified != current_classified:
        # An unclassified root defines the module version.
        return current_classified
    return compare_maven_versions(candidate.version, current.version) == 1

def _select_gradle_forced_versions(artifacts):
    """Selects the single version to force for each Gradle group:artifact module.

    Gradle resolves one version per module regardless of classifier, so forcing
    two versions of the same module (for example a main jar and its
    test-fixtures jar) makes resolution unsatisfiable.
    """
    winners = {}
    for artifact in artifacts:
        if not getattr(artifact, "version", None):
            continue
        key = "%s:%s" % (artifact.group, artifact.artifact)
        current = winners.get(key)
        if current == None or _defines_gradle_module_version(artifact, current):
            winners[key] = artifact
    return {key: winner.version for key, winner in winners.items()}

def _forces_gradle_module_version(artifact, forced_versions):
    version = getattr(artifact, "version", None)
    if not version:
        return False
    return version == forced_versions.get("%s:%s" % (artifact.group, artifact.artifact))

def apply_root_version_conflict_policy(artifacts, resolver, version_conflict_policy):
    """Applies the install-level conflict policy to root module artifacts."""
    if resolver not in ["gradle", "maven"] or version_conflict_policy != "pinned":
        return artifacts

    if resolver == "gradle":
        forced_versions = _select_gradle_forced_versions(artifacts)
        return [
            struct(**(remove_fields(artifact) | {"force_version": True})) if _forces_gradle_module_version(artifact, forced_versions) else artifact
            for artifact in artifacts
        ]

    return [
        struct(**(remove_fields(artifact) | {"force_version": True})) if getattr(artifact, "version", None) else artifact
        for artifact in artifacts
    ]
