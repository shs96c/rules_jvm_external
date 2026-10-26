# Copyright 2026 The Bazel Authors. All rights reserved.
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
# limitations under the License.

"""Compact resolved records and their repository-independent integrity checks."""

load("//private/lib:coordinates.bzl", "to_external_form", "to_key", "unpack_coordinates")

def coordinates_from_identity(identity, version):
    parts = identity.split(":")
    return {
        "group": parts[0],
        "artifact": parts[1],
        "version": version,
        "packaging": parts[2] if len(parts) > 2 else "jar",
        "classifier": parts[3] if len(parts) > 3 else "jar",
    }

def metadata(row):
    return row[3] if len(row) == 4 else {}

def records_by_identity(contents):
    records = {}
    for row in contents["artifacts"]:
        if type(row) != "list" or len(row) not in [3, 4] or type(row[0]) != "string":
            fail("Invalid artifact record; expected [coordinate, SHA-256, hash, optional metadata]")
        parsed = unpack_coordinates(row[0])
        if not parsed.version or to_external_form(parsed) != row[0]:
            fail("Artifact coordinate must use the full Gradle external form: %s" % row[0])
        if row[1] != None and (type(row[1]) != "string" or len(row[1]) != 64 or not all([c in "0123456789abcdef" for c in row[1].elems()])):
            fail("Invalid SHA-256 for %s" % row[0])
        if type(metadata(row)) != "dict":
            fail("Invalid artifact metadata: %s" % row[0])
        for key in ["requests", "variants"]:
            if key in metadata(row) and type(metadata(row)[key]) != "list":
                fail("Invalid %s metadata for %s" % (key, row[0]))
        identity = to_key(parsed)
        if identity in records:
            fail("Duplicate artifact identity: %s" % identity)
        records[identity] = row
    return records

def row_hash(row, children, local, skipped):
    """Hash own data and immediate identities, without propagating child updates."""
    return hash(json.encode([row[0], row[1], sorted(children), metadata(row), local, skipped]))

def compute_hashes(contents):
    records = records_by_identity(contents)
    dependencies = contents.get("dependencies", {})
    local = contents.get("m2local_artifacts", [])
    skipped = contents.get("skipped", [])
    hashes = {}
    for identity, row in records.items():
        references = dependencies.get(identity, []) + metadata(row).get("variants", [])
        valid = all([child in records for child in references])

        # Invalid hashes retain the ordinary warning and REPIN recovery path.
        hashes[identity] = row_hash(row, dependencies.get(identity, []), identity in local, identity in skipped) if valid else None
    for identity in list(dependencies) + local + skipped:
        if identity not in records:
            hashes["__missing__:" + identity] = None
    if local and not contents.get("m2local"):
        hashes["__m2local__"] = None
    return hashes

def stored_hashes(contents):
    return {identity: row[2] for identity, row in records_by_identity(contents).items() if type(row[2]) == "int"}

def records_from_v3(contents):
    """Expand legacy grouped checksums into independently versioned records."""
    records = {}
    for identity, info in contents["artifacts"].items():
        for classifier, sha in info["shasums"].items():
            parsed = coordinates_from_identity(identity, info["version"])
            parsed["classifier"] = classifier
            coordinate = to_external_form(parsed)
            records[coordinate] = [coordinate, sha, 0]
    identities = {to_key(row[0]): True for row in records.values()}
    for identity in contents.get("skipped", []):
        if identity in identities:
            continue
        parsed = coordinates_from_identity(identity, "")
        versions = {
            unpack_coordinates(row[0]).version: True
            for row in records.values()
            if row[0].startswith("%s:%s:" % (parsed["group"], parsed["artifact"])) and (unpack_coordinates(row[0]).packaging or "jar") == parsed["packaging"]
        }
        if len(versions) != 1:
            fail("Cannot recover version for skipped artifact %s" % identity)
        parsed["version"] = versions.keys()[0]
        coordinate = to_external_form(parsed)
        records[coordinate] = [coordinate, None, 0]
    return [records[coordinate] for coordinate in sorted(records)]
