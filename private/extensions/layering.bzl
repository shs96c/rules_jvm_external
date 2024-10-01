load("@bazel_skylib//lib:structs.bzl", "structs")
load("//:specs.bzl", "parse")
load("//private/lib:artifacts.bzl", _artifacts = "artifacts")
load("//private/rules:coursier.bzl", "DEFAULT_AAR_IMPORT_LABEL", "coursier_fetch", "pinned_coursier_fetch")

DEFAULT_REPOSITORIES = [
    "https://repo1.maven.org/maven2",
]

DEFAULT_NAME = "maven"

_DEFAULT_RESOLVER = "coursier"

artifact = tag_class(
    attrs = {
        "name": attr.string(default = DEFAULT_NAME),
        "group": attr.string(mandatory = True),
        "artifact": attr.string(mandatory = True),
        "version": attr.string(),
        "packaging": attr.string(),
        "classifier": attr.string(),
        "force_version": attr.bool(default = False),
        "neverlink": attr.bool(),
        "testonly": attr.bool(),
        "exclusions": attr.string_list(doc = "Maven artifact tuples, in `artifactId:groupId` format", allow_empty = True),
    },
)

install = tag_class(
    attrs = {
        "name": attr.string(default = DEFAULT_NAME),

        # Actual artifacts and overrides
        "artifacts": attr.string_list(doc = "Maven artifact tuples, in `artifactId:groupId:version` format", allow_empty = True),
        "boms": attr.string_list(doc = "Maven BOM tuples, in `artifactId:groupId:version` format", allow_empty = True),
        "exclusions": attr.string_list(doc = "Maven artifact tuples, in `artifactId:groupId` format", allow_empty = True),

        # What do we fetch?
        "fetch_javadoc": attr.bool(default = False),
        "fetch_sources": attr.bool(default = False),

        # How do we do artifact resolution?
        "resolver": attr.string(doc = "The resolver to use. Only honoured for the root module.", values = ["coursier", "maven"], default = _DEFAULT_RESOLVER),

        # Controlling visibility
        "strict_visibility": attr.bool(
            doc = """Controls visibility of transitive dependencies.

            If "True", transitive dependencies are private and invisible to user's rules.
            If "False", transitive dependencies are public and visible to user's rules.
            """,
            default = False,
        ),
        "strict_visibility_value": attr.label_list(default = ["//visibility:private"]),

        # Android support
        "aar_import_bzl_label": attr.string(default = DEFAULT_AAR_IMPORT_LABEL, doc = "The label (as a string) to use to import aar_import from"),
        "use_starlark_android_rules": attr.bool(default = False, doc = "Whether to use the native or Starlark version of the Android rules."),

        # Configuration "stuff"
        "additional_netrc_lines": attr.string_list(doc = "Additional lines prepended to the netrc file used by `http_file` (with `maven_install_json` only).", default = []),
        "use_credentials_from_home_netrc_file": attr.bool(doc = "Whether to pass machine login credentials from the ~/.netrc file to coursier.", default = False),
        "duplicate_version_warning": attr.string(
            doc = """What to do if there are duplicate artifacts

            If "error", then print a message and fail the build.
            If "warn", then print a warning and continue.
            If "none", then do nothing.
            """,
            default = "warn",
            values = [
                "error",
                "warn",
                "none",
            ],
        ),
        "fail_if_repin_required": attr.bool(doc = "Whether to fail the build if the maven_artifact inputs have changed but the lock file has not been repinned.", default = False),
        "lock_file": attr.label(),
        "repositories": attr.string_list(default = DEFAULT_REPOSITORIES),
        "generate_compat_repositories": attr.bool(
            doc = "Additionally generate repository aliases in a .bzl file for all JAR artifacts. For example, `@maven//:com_google_guava_guava` can also be referenced as `@com_google_guava_guava//jar`.",
        ),

        # When using an unpinned repo
        "excluded_artifacts": attr.string_list(doc = "Artifacts to exclude, in `artifactId:groupId` format. Only used on unpinned installs", default = []),  # list of artifacts to exclude
        "fail_on_missing_checksum": attr.bool(default = True),
        "resolve_timeout": attr.int(default = 600),
        "version_conflict_policy": attr.string(
            doc = """Policy for user-defined vs. transitive dependency version conflicts

            If "pinned", choose the user-specified version in maven_install unconditionally.
            If "default", follow Coursier's default policy.
            """,
            default = "default",
            values = [
                "default",
                "pinned",
            ],
        ),
        "ignore_empty_files": attr.bool(default = False, doc = "Treat jars that are empty as if they were not found."),
        "repin_instructions": attr.string(doc = "Instructions to re-pin the repository if required. Many people have wrapper scripts for keeping dependencies up to date, and would like to point users to that instead of the default. Only honoured for the root module."),
        "additional_coursier_options": attr.string_list(doc = "Additional options that will be passed to coursier."),
    },
)

override = tag_class(
    attrs = {
        "name": attr.string(default = DEFAULT_NAME),
        "coordinates": attr.string(doc = "Maven artifact tuple in `artifactId:groupId` format", mandatory = True),
        "target": attr.label(doc = "Target to use in place of maven coordinates", mandatory = True),
    },
)

def maven_impl(mctx):
    root_modules = gather_modules(mctx, True)
    non_root_modules = gather_modules(mctx, False)
    merged_workspaces = merge_modules(root_modules, non_root_modules)

    for workspace in merged_workspaces:
        owning_modules = workspace["owning_modules"]
        if len(owning_modules) > 1:
            print("`%s` is declared in more than one module:" % workspace["name"], ", ".join(sorted(owning_modules)))

    for workspace in merged_workspaces:
        generate_workspace(workspace)

def gather_modules(mctx, only_root):
    # Returns a data structure like:
    #
    # {
    #     "rules_jvm_external": [
    #         {
    #             "name": "maven",
    #             "artifacts": [],
    #         },
    #         {
    #             "name": "something_else",
    #             "artifacts": [],
    #         },
    #     ],
    # }
    #
    # We can do this because we know each `install` tag can only appear once
    # in a given module, and we'll have merged all the tag classes once we've
    # finished processing everything.

    module_to_values = {}

    for module in mctx.modules:
        if module.is_root != only_root:
            continue

        module_to_values.update({module.name: process_tags(module)})

    return module_to_values

def process_tags(module):
    maven_install_name_to_values = {}

    for install in module.tags.install:
        value = structs.to_dict(install)
        if maven_install_name_to_values.get("name", None):
            fail("Only one `install` with a given `name` can be in a single module file. Conflicting name was:", value["name"])
        value["owning_modules"] = [module.name]

        # Fix up the artifacts and boms
        original_artifacts = value.pop("artifacts", [])
        artifacts = _artifacts.create()
        for item in original_artifacts:
            _artifacts.add(artifacts, item)
        value["artifacts"] = artifacts

        original_boms = value.pop("boms", [])
        boms = _artifacts.create()
        for item in original_boms:
            boms = _artifacts.add(boms, item)
        value["boms"] = boms

        maven_install_name_to_values.update({value["name"]: value})

    for artifact in module.tags.artifact:
        value = structs.to_dict(artifact)
        name = value.pop("name")

        workspace = maven_install_name_to_values.get(name, {"owning_modules": [module.name]})
        artifacts = workspace.get("artifacts", _artifacts.create())
        _artifacts.add(artifacts, value)
        workspace["artifacts"] = artifacts

    return maven_install_name_to_values.values()

_LOGICAL_OR = [
    "fetch_javadoc",
    "fetch_sources",
    "generate_compat_repositories",
    "fail_on_missing_checksum",
]

_MERGE = [
    "boms",
    "artifacts",
]

_APPEND = [
    "additional_netrc_lines",
    "excluded_artifats",
    "owning_modules",
    "repositories",
]

_ROOT_MODULE_APPEND = [
    "owning_modules",
]

_ROOT_TAKES_PRECEDENCE = [
    "lock_file"
]

_ROOT_LOGICAL_OR = [
    "generate_compat_repositories",
]

def merge_modules(root_modules, non_root_modules):
    merged = {}

    root_workspaces = {}
    for module in root_modules.values():
        for aggregated_tags in module:
            root_workspaces[aggregated_tags["name"]] = aggregated_tags

    # To start with, make sure we have all the non-root modules in `merged`
    for (module_name, aggregated_tags) in non_root_modules.items():
        for workspace in aggregated_tags:
            current = merged.get(workspace["name"], {})

            for (key, value) in workspace.items():
                if key in _LOGICAL_OR:
                    current[key] = current.get(key, False) or value
                elif key in _MERGE:
                    current[key] = _artifacts.merge(value, current.get(key, _artifacts.create()))
                elif key in _APPEND:
                    current[key] = current.get(key, []) + value
                else:
                    # Does the key exist in a root module? If it does,
                    # continue as we'll replace the value later
                    root = root_workspaces.get(workspace["name"], {})
                    if key in root.keys() and root[key]:
                        current[key] = value
                        continue;

                    # If the values differ between what we have already and what we're about to add, fail
                    if key in current.keys() and value != current[key]:
                        fail("More than one module declares a value for", key, "in maven.install named", workspace["name"] ,"most recently seen in", module_name)

                    current[key] = value

            merged[current["name"]] = current

    # Now we have that, repeat the process, but for the `root_modules`
    for (module_name, aggregated_tags) in root_modules.items():
        for workspace in aggregated_tags:
            current = merged.get(workspace["name"], {})

            for (key, value) in workspace.items():
                if key in _ROOT_LOGICAL_OR:
                    current[key] = current.get(key, False) or value
                elif key in _MERGE:
                    # Rather than merging, we need to iterate over the values and `set` them
                    artifacts = current.get(key, _artifacts.create())
                    for item in _artifacts.to_list(value):
                        _artifacts.set(artifacts, item)
                    current[key] = artifacts
                elif key in _ROOT_MODULE_APPEND:
                    current[key] = current.get(key, []) + value
                else:
                    current[key] = value

            merged[current["name"]] = current

    return merged.values()

def generate_workspace(workspace):
    artifacts_json = [json.encode(a) for a in _artifacts.to_list(workspace.get("artifacts", _artifacts.create()))]
    boms_json = [json.encode(a) for a in _artifacts.to_list(workspace.get("boms", _artifacts.create()))]
    repositories_json = [json.encode({"repo_url": r}) for r in workspace["repositories"]]

    if workspace.get("resolver", _DEFAULT_RESOLVER) == "coursier":
        name = workspace["name"]

        coursier_fetch(
            # Name this repository "unpinned_{name}" if the user specified a
            # maven_install.json file. The actual @{name} repository will be
            # created from the maven_install.json file in the coursier_fetch
            # invocation after this.
            name = name,
#            name = "unpinned_" + name if workspace.get("lock_file") else name,
            pinned_repo_name = name if workspace.get("lock_file") else None,
            user_provided_name = name,
            repositories = repositories_json,
            artifacts = artifacts_json,
            fail_on_missing_checksum = workspace.get("fail_on_missing_checksum"),
            fetch_sources = workspace.get("fetch_sources"),
            fetch_javadoc = workspace.get("fetch_javadoc"),
            excluded_artifacts = None, #excluded_artifacts_json,
            generate_compat_repositories = False,
            version_conflict_policy = workspace.get("version_conflict_policy"),
            override_targets = None, #overrides,
            strict_visibility = workspace.get("strict_visibility"),
            strict_visibility_value = workspace.get("strict_visibility_value"),
            use_credentials_from_home_netrc_file = workspace.get("use_credentials_from_home_netrc_file"),
            maven_install_json = workspace.get("lock_file"),
            resolve_timeout = workspace.get("resolve_timeout"),
            use_starlark_android_rules = workspace.get("use_starlark_android_rules"),
            aar_import_bzl_label = workspace.get("aar_import_bzl_label"),
            duplicate_version_warning = workspace.get("duplicate_version_warning"),
            ignore_empty_files = workspace.get("ignore_empty_files"),
            additional_coursier_options = workspace.get("additional_coursier_options"),
        )

maven = module_extension(
    maven_impl,
    tag_classes = {
        "artifact": artifact,
        "install": install,
        "override": override,
    },
)
