# Copyright 2023 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and

load(":maven_utils.bzl", "unpack_coordinates")

_REQUIRED_KEYS = ["artifacts", "dependencies", "repositories", "shasums"]

def _is_valid_lock_file(lock_file_contents):
    version = lock_file_contents.get("version")
    if "2" != version:
        return False

    all_keys = lock_file_contents.keys()

    for key in _REQUIRED_KEYS:
        if key not in all_keys:
            return False

    return True

def _get_input_artifacts_hash(lock_file_contents):
    return lock_file_contents.get("__INPUT_ARTIFACTS_HASH")

def _get_lock_file_hash(lock_file_contents):
    return lock_file_contents.get("__RESOLVED_ARTIFACTS_HASH")

def _compute_lock_file_hash(lock_file_contents):
    to_hash = {}
    for key in _REQUIRED_KEYS:
        # The lock file already has sorted content, so this is enough
        to_hash.update({key: lock_file_contents.get(key)})
    return hash(repr(to_hash))

def _to_m2_path(unpacked):
    path = "{group}/{artifact}/{version}/{artifact}-{version}".format(
        artifact = unpacked.artifactId,
        group = unpacked.groupId.replace(".", "/"),
        version = unpacked.version,
    )

    classifier = unpacked.scope if unpacked.scope else "jar"
    if "jar" != classifier:
        path += "-%s" % classifier

    extension = unpacked.type if unpacked.type else "jar"
    path += ".%s" % extension

    return path

def _to_key(coords):
    return coords.rsplit(":", 1)[0]

def _create_artifact(coord, key, key2coord, shasums, dependencies, repositories, files):
    unpacked = unpack_coordinates(coord)

    # The shasums use a key derived from the `jar` extension
    # groupId:artifactId[:type[:scope]]:version
    shasum_key = "%s:%s" % (unpacked.groupId, unpacked.artifactId)
    if unpacked.type != None and "" != unpacked.type and "jar" != unpacked.type:
        shasum_key += ":%s" % unpacked.type

    scope = unpacked.scope if unpacked.scope else "jar"
    if not shasums.get(shasum_key) or not shasums[shasum_key].get(scope):
        return None

    deps = [key2coord[dep] if dep in key2coord else dep for dep in dependencies.get(key, [])]

    m2_path = _to_m2_path(unpacked)
    urls = []
    for (repo, entries) in repositories.items():
        if key in entries:
            urls.append(repo + m2_path)
    if len(urls) == 0:
        urls.append(None)

    if not shasums.get(shasum_key):
        fail("Key is %s and shasums are %s" % (shasum_key, shasums.keys()))
    if not shasums[shasum_key].get(scope):
        fail("Key is %s and shasums are %s" % (scope, shasums[shasum_key]))

    return {
        "coordinates": coord,
        "file": files.get(coord, m2_path),
        "sha256": shasums[shasum_key][scope],
        "deps": deps,
        "urls": urls,
    }

def _get_artifacts(lock_file_contents):
    key2coord = {_to_key(a): a for a in lock_file_contents["artifacts"]}
    shasums = lock_file_contents["shasums"]
    dependencies = lock_file_contents["dependencies"]
    repositories = lock_file_contents["repositories"]
    files = lock_file_contents.get("files", {})

    to_return = []
    skipped = lock_file_contents.get("skipped", [])

    for coord in lock_file_contents["artifacts"]:
        if coord in skipped:
            to_return.append({
                "coordinates": coord,
                "file": None,
                "sha256": None,
                "deps": [key2coord[dep] if dep in key2coord else dep for dep in dependencies.get(key, [])],
                "urls": [],
            })
            continue

        key = _to_key(coord)

        main = _create_artifact(
            coord = coord,
            key = key,
            key2coord = key2coord,
            shasums = shasums,
            dependencies = dependencies,
            repositories = repositories,
            files = files,
        )
        to_return.append(main)

        unpacked = unpack_coordinates(coord)

        source_coord = "{group}:{artifact}:jar:sources:{version}".format(
            artifact = unpacked.artifactId,
            group = unpacked.groupId,
            version = unpacked.version,
        )
        source = _create_artifact(
            coord = source_coord,
            key = key,
            key2coord = key2coord,
            shasums = shasums,
            dependencies = {},
            repositories = repositories,
            files = files,
        )
        if source:
            to_return.append(source)

        javadoc_coord = "{group}:{artifact}:jar:javadoc:{version}".format(
            artifact = unpacked.artifactId,
            group = unpacked.groupId,
            version = unpacked.version,
        )
        javadoc = _create_artifact(
            coord = javadoc_coord,
            key = key,
            key2coord = key2coord,
            shasums = shasums,
            dependencies = {},
            repositories = repositories,
            files = files,
        )
        if javadoc:
            to_return.append(javadoc)

    return to_return

def _get_netrc_entries(lock_file_contents):
    return {}

def _render_lock_file(lock_file_contents, input_hash):
    # We would like to use `json.encode_indent` but that sorts dictionaries, and
    # we've carefully preserved ordering. So we need to handle this ourselves.
    contents = [
        "{",
        "  \"__AUTOGENERATED_FILE_DO_NOT_MODIFY_THIS_FILE_MANUALLY\": \"THERE_IS_NO_DATA_ONLY_ZUUL\",",
        "  \"__INPUT_ARTIFACTS_HASH\": %s," % input_hash,
        "  \"__RESOLVED_ARTIFACTS_HASH\": %s," % _compute_lock_file_hash(lock_file_contents),
    ]
    contents.append("  \"artifacts\": %s," % json.encode_indent(lock_file_contents["artifacts"], prefix = "  ", indent = "  "))
    contents.append("  \"dependencies\": %s," % json.encode_indent(lock_file_contents["dependencies"], prefix = "  ", indent = "  "))
    if lock_file_contents.get("skipped"):
        contents.append("  \"skipped\": %s," % json.encode_indent(lock_file_contents["skipped"], prefix = "  ", indent = "  "))
    contents.append("  \"packages\": %s," % json.encode_indent(lock_file_contents["packages"], prefix = "  ", indent = "  "))
    if lock_file_contents.get("m2local"):
        contents.append("  \"m2local\": true,")
    contents.append("  \"repositories\": {")

    items = lock_file_contents["repositories"].items()
    count = len(items)
    for (repo, artifacts) in items:
        count = count - 1
        to_append = "    \"%s\": %s" % (repo, json.encode_indent(artifacts, prefix = "    ", indent = "  "))
        if count:
            to_append += ","
        contents.append(to_append)
    contents.append("  },")
    contents.append("  \"shasums\": %s," % json.encode_indent(lock_file_contents["shasums"], prefix = "  ", indent = "  "))
    contents.append("  \"version\": \"2\"")
    contents.append("}")
    contents.append("")

    return "\n".join(contents)

v2_lock_file = struct(
    is_valid_lock_file = _is_valid_lock_file,
    get_input_artifacts_hash = _get_input_artifacts_hash,
    get_lock_file_hash = _get_lock_file_hash,
    compute_lock_file_hash = _compute_lock_file_hash,
    get_artifacts = _get_artifacts,
    get_netrc_entries = _get_netrc_entries,
    render_lock_file = _render_lock_file,
)
