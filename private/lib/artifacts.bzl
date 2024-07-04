load("//:specs.bzl", "parse")

_UNKNOWN_VERSION = "unknown"

def _new_artifacts():
    return {}

def _add(artifacts, artifact):
    parsed = parse.parse_artifact_spec_list([artifact])[0]
    module_name = "{group}:{artifact}".format(group = parsed["group"], artifact = parsed["artifact"])
    existing = artifacts.get(module_name, {})
    version = parsed.get("version", _UNKNOWN_VERSION)

    parsed.pop("group")
    parsed.pop("artifact")
    parsed.pop("version", None)

    if version in existing.keys():
        if existing[version] != parsed:
            print("Attempting to merge {module}:{version} but they differ: {left} -> {right}".format(
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
