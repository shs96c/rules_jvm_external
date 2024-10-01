load("@bazel_skylib//lib:structs.bzl", "structs")
load("//:specs.bzl", "parse")

# We keep artifacts in a trie-like structure. The first thing we do is parse
# the artifact into a `dict` via `parse._parse_maven_coordinate_string`. Once
# this is done, we use the `group` as the first key, then the artifact, then
# create a list of version numbers with any extra attributes. We end up with
# something that looks like:
#
# {
#   "com.google.guava": {
#     "guava": {
#       "33.1.0": {
#         "classifier": "jar",
#         "testonly": True,
#       },
#       "31.1": {
#       },
#     }
#   },
#   "org.seleniumhq.selenium": {
#     "selenium-java": {
#       "4.18.1": {
#       },
#     },
#   },
# }
#
# This allows us to express the fairly common case where there are multiple
# versions of the same dep within the workspace. The trade-off is that if
# these only differ by additional fields (eg. `testonly`) we lose that data.
# Given that people really shouldn't be doing that, it seems like a decent
# trade-off to make.

def _create():
    return {}

def _merge(into, to_be_merged):
    for (group_name, all_artifacts) in to_be_merged.items():
        for (artifact_name, all_versions) in all_artifacts.items():
            for (version, data) in all_versions.items():
                group = into.get(group_name, {})
                artifact = group.get(artifact_name, {})
                artifact[version] = data
                group[artifact_name] = artifact
                into[group_name] = group
    return into

_IGNORED_KEYS = ["group", "artifact", "version", "to_json", "to_proto"]
_DEFAULT_VERSION_KEY = "rje-says-this-version-does-not-exist"

def _to_mergeable_form(artifact):
    # Convert from a string into something more structured
    if "string" == type(artifact):
        artifact = parse.parse_artifact_spec_list([artifact])[0]

    # Make sure we're dealing with a `dict` from here on as it makes life simpler
    artifact = artifact if "dict" == type(artifact) else structs.to_dict(artifact)

    keys = artifact.keys()
    if "group" in keys and "artifact" in keys:
        # Looks like the output from parsing a maven coordinates string
        leaf = {key: value for (key, value) in artifact.items() if key not in _IGNORED_KEYS}
        version = artifact["version"] if artifact["version"] else _DEFAULT_VERSION_KEY

        return {
            artifact["group"]: {
                artifact["artifact"]: {
                    version: leaf,
                },
            },
        }

    return artifact

def _add(existing, artifact):
    to_merge = _to_mergeable_form(artifact)
    _merge(existing, to_merge)

def _set(existing, artifact):
    to_merge = _to_mergeable_form(artifact)

    for (group_name, all_artifacts) in to_merge.items():
        group = existing.get(group_name, {})
        for (artifact_name, value) in all_artifacts.items():
            group[artifact_name] = value
            existing[group_name] = group

def _get_duplicates(artifacts):
    duplicates = {}

    for (group_name, all_artifacts) in sorted(artifacts.items()):
        for (artifact_name, all_versions) in sorted(all_artifacts.items()):
            if len(all_versions) > 1:
                duplicates["%s:%s" % (group_name, artifact_name)] = all_versions.keys()

    return duplicates

def _to_argument_list(to_convert):
    to_return = []

    for (group_name, all_artifacts) in sorted(to_convert.items()):
        for (artifact_name, all_versions) in sorted(all_artifacts.items()):
            for (version, additional_fields) in sorted(all_versions.items()):
                artifact = {
                    "group": group_name,
                    "artifact": artifact_name,
                }
                if version != _DEFAULT_VERSION_KEY:
                    artifact.update({"version": version})
                artifact.update(**additional_fields)
                to_return.append(artifact)

    return to_return

artifacts = struct(
    create = _create,
    add = _add,
    set = _set,
    merge = _merge,
    get_duplicates = _get_duplicates,
    to_list = _to_argument_list,
)
