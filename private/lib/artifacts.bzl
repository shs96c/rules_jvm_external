load("@bazel_skylib//lib:structs.bzl", "structs")
load("//:specs.bzl", "parse")

_UNKNOWN_VERSION = "unknown"

def _amend_exclusions(item):
    if "exclusions" not in item.keys():
        return item

    to_return = {}
    to_return.update(item)

    exclusions = parse.parse_exclusion_spec_list(item["exclusions"])
    print(item["exclusions"], "->", exclusions)
    to_return["exclusions"] = sorted(["%s:%s" % (i["group"], i["artifact"]) for i in exclusions])
    print(sorted(["%s:%s" % (i["group"], i["artifact"]) for i in exclusions]))
    print(to_return["exclusions"])

    return to_return

def _new_artifacts(array_of_dicts_or_struct = []):
    to_return = {}

    for item in array_of_dicts_or_struct:
        _add(to_return, item)

    return to_return

def _add(artifacts, to_add):
    if type(to_add) == "string" or type(to_add) == "dict":
        artifact = to_add
    else:
        artifact = structs.to_dict(to_add)

    parsed = parse.parse_artifact_spec_list([artifact])[0]
    parsed = _amend_exclusions(parsed)
    module_name = "{group}:{artifact}".format(group = parsed["group"], artifact = parsed["artifact"])
    existing = artifacts.get(module_name, {})
    version = parsed.get("version", _UNKNOWN_VERSION)

    parsed.pop("group")
    parsed.pop("artifact")
    parsed.pop("version", None)

    if version in existing.keys():
        if existing[version] != parsed:
            print("Attempting to merge {module}:{version} but extra values differ: {left} -> {right}. Selecting {right}".format(
                left = existing[version],
                module = module_name,
                right = parsed,
                version = version,
            ))
    existing[version] = parsed
    artifacts[module_name] = existing

def _to_list(artifacts):
    to_return = []
    for (module, versions) in sorted(artifacts.items()):
        (group, artifact) = module.split(":", 2)
        for (version, remainder) in sorted(versions.items()):
            item = {
                "group": group,
                "artifact": artifact,
            }
            if version != _UNKNOWN_VERSION and version:
                item.update({"version": version})
            item.update(remainder)
            to_return.append(item)
    return to_return

artifacts = struct(
    new = _new_artifacts,
    add = _add,
    to_list = _to_list,
)
