load("@bazel_skylib//lib:structs.bzl", "structs")
load("//:specs.bzl", "parse")
load("//private/lib:coordinates.bzl", "unpack_coordinates")
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
    merged_modules = merge_modules(root_modules, non_root_modules)

    pass

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
        maven_install_name_to_values.update({value["name"]: value})

    for artifact in module.tags.artifact:
        value = structs.to_dict(artifact)
        name = value.pop("name")

        workspace = maven_install_name_to_values.get(name, {"artifacts": [], "owning_modules": [module.name]})
        workspace["artifacts"] = workspace["artifacts"] + [value]

    return maven_install_name_to_values.values()

_LOGICAL_OR = [
    "fetch_javadoc",
    "fetch_sources",
    "generate_compat_repositories",
    "fail_on_missing_checksum",
]

_APPEND = [
    "additional_netrc_lines",
    "artifacts",
    "boms",
    "excluded_artifats",
    "owning_modules",
    "repositories",
]

def merge_modules(root_modules, modules):
    merged = {}

    root_workspace_names = []
    for module in root_modules.values():
        for aggregated_tags in module:
            root_workspace_names.append(aggregated_tags["name"])

    print(root_workspace_names)

    #    for (module_name, aggregated_tags) in modules.items():
    #        for workspace in aggregated_tags:
    #            current = merged.get(workspace["name"], {})
    #
    #            for (key, value) in workspace.items():
    #                if key in _LOGICAL_OR:
    #                    current[key] = current.get(key, False) or value
    #                elif key in _APPEND:
    #                    current[key] = current.get(key, []) + value
    #                else:
    #                    if key in merged.keys() and value != merged[key] and current["name"] not in root_module_names:
    #                        fail("More than one module declares a value for ", key, "most recently seen in", module_name)
    #                    current[key] = value
    #
    #            merged[current["name"]] = current

    return merged

maven = module_extension(
    maven_impl,
    tag_classes = {
        "artifact": artifact,
        "install": install,
        "override": override,
    },
)
