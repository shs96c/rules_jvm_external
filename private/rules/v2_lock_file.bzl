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

def _create_artifact(coord, key, key2coord, shasums, dependencies, repositories):
    unpacked = unpack_coordinates(coord)

    # The shasums use a key derived from the `jar` extension
    # groupId:artifactId[:type[:scope]]:version
    shasum_key = "%s:%s" % (unpacked.groupId, unpacked.artifactId)
    if unpacked.type != None and "" != unpacked.type and "jar" != unpacked.type:
        shasum_key += ":%s" % unpacked.type

    scope = unpacked.scope if unpacked.scope else "jar"
    if not shasums.get(shasum_key) or not shasums[shasum_key].get(scope):
        return None

    file = _to_m2_path(unpacked)

    deps = [key2coord[dep] if dep in key2coord else dep for dep in dependencies.get(key, [])]

    urls = []
    for (repo, entries) in repositories.items():
        if key in entries:
            urls.append(repo + file)
    if len(urls) == 0:
        urls.append(None)

    if not shasums.get(shasum_key):
        fail("Key is %s and shasums are %s" % (shasum_key, shasums.keys()))
    if not shasums[shasum_key].get(scope):
        fail("Key is %s and shasums are %s" % (scope, shasums[shasum_key]))

    return {
        "coordinates": coord,
        "file": file,
        "sha256": shasums[shasum_key][scope],
        "deps": deps,
        "urls": urls,
    }

def _get_artifacts(lock_file_contents):
    key2coord = {_to_key(a): a for a in lock_file_contents["artifacts"]}
    shasums = lock_file_contents["shasums"]
    dependencies = lock_file_contents["dependencies"]
    repositories = lock_file_contents["repositories"]

    to_return = []

    for coord in lock_file_contents["artifacts"]:
        key = _to_key(coord)

        main = _create_artifact(
            coord = coord,
            key = key,
            key2coord = key2coord,
            shasums = shasums,
            dependencies = dependencies,
            repositories = repositories,
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
        )
        if javadoc:
            to_return.append(javadoc)

    return to_return

def _get_netrc_entries(lock_file_contents):
    return {}

v2_lock_file = struct(
    is_valid_lock_file = _is_valid_lock_file,
    get_input_artifacts_hash = _get_input_artifacts_hash,
    get_lock_file_hash = _get_lock_file_hash,
    compute_lock_file_hash = _compute_lock_file_hash,
    get_artifacts = _get_artifacts,
    get_netrc_entries = _get_netrc_entries,
)
