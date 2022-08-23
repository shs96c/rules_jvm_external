load("//:specs.bzl", "parse")
load("//private/rules:maven_utils.bzl", "unpack_coordinates")
load(":download_pinned_deps.bzl", "download_pinned_deps")
load(":generate_pinned_repo.bzl", "generate_pinned_repo")

_install = tag_class(
    attrs = {
        "name": attr.string(
            default = "maven",
        ),
        "artifacts": attr.string_list(),
        "exclusions": attr.string_list(),
        "lock_file": attr.label(),
        "repositories": attr.string_list(
            default = ["https://repo1.maven.org/maven2"],
        ),
    },
)

def _parse_artifact(spec):
    if type(spec) == "string":
        return unpack_coordinates(spec)
    return spec

def _maven_impl(mctx):
    repos = {}

    for mod in mctx.modules:
        for install in mod.tags.install:
            repo = repos.get(install.name, {})

            artifacts = repo.get("artifacts", [])
            [artifacts.append(a) for a in install.artifacts]
            repo["artifacts"] = artifacts

            repositories = repo.get("repositories", [])
            for r in install.repositories:
                if not r in repositories:
                    repositories.append(r)
            repo["repositories"] = repositories

            if install.lock_file:
                lock_file = repo.get("lock_file", None)
                if lock_file and lock_file != install.lock_file:
                    fail("There can only be one lock file. Values were %s and %s" % (lock_file, install.lock_file))
                repo["lock_file"] = install.lock_file

            repos[install.name] = repo

    existing_repos = []
    for (name, repo) in repos.items():
        artifacts_json_strings = []
        for artifact in repo["artifacts"]:
            artifacts_json_strings.append(json.encode(_parse_artifact(artifact)))

        if repo.get("lock_file", None):
            lock_file = json.decode(mctx.read(mctx.path(repo.get("lock_file"))))
            artifacts = [json.decode(a) for a in artifacts_json_strings]

            dep_tree = lock_file["dependency_tree"]

            created = download_pinned_deps(dep_tree = dep_tree, artifacts = artifacts, existing_repos = existing_repos)
            existing_repos.extend(created)

            generate_pinned_repo(
                name = name,
                artifacts = artifacts_json_strings,
                lock_file = repo["lock_file"],
                maven_install_json = repo["lock_file"],
            )

maven = module_extension(
    _maven_impl,
    tag_classes = {
        "install": _install,
    },
)
