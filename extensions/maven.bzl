load("@bazel_features//:features.bzl", "bazel_features")
load("@bazel_skylib//lib:structs.bzl", "structs")
load("//private/lib:coordinates.bzl", "to_external_form", "unpack_coordinates")
load("//private/rules:coursier.bzl", "DEFAULT_AAR_IMPORT_LABEL", "coursier_fetch", "pinned_coursier_fetch")

DEFAULT_NAME = "maven"

DEFAULT_REPOSITORIES = [
    "https://repo1.maven.org/maven2",
]

DEFAULT_RESOLVER = "coursier"

_DEFAULTS_DOCS = """Sets default values to be used by all resolutions unless overridden by an `install` tag.

Rulesets that are distributed by the BCR are never expected to use this
facility, nor are they expected to override the values in the `defaults`
tag in the own `install` tags. This allows individual projects to ensure
that their defaults are respected.

Users of this are expected to be teams sharing default configuration values
between projects within a single company, possibly in a ruleset provided in
their own module registry.
"""

artifact_tag = tag_class(
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

install_tag = tag_class(
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
        "resolver": attr.string(doc = "The resolver to use.", values = ["coursier", "maven"], default = DEFAULT_RESOLVER),

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

override_tag = tag_class(
    attrs = {
        "name": attr.string(default = DEFAULT_NAME),
        "coordinates": attr.string(doc = "Maven artifact tuple in `artifactId:groupId` format", mandatory = True),
        "target": attr.label(doc = "Target to use in place of maven coordinates", mandatory = True),
    },
)

def explode(artifacts):
    return [unpack_coordinates(a) for a in artifacts]

def logical_or(left, right):
    return left or right

def set_but_error_if_different(property_name, default_value, left, right, right_is_root):
    if right_is_root:
        left[property_name] = right[property_name]
        if property_name in left["errors"]:
            left["errors"].remove(property_name)
        return

    if left.get(property_name, default_value) != right.get(property_name, default_value):
        left["errors"].append(property_name)

_EMPTY_MODULE = {
    "name": None,
    "artifacts": [],
    "boms": [],
    "exclusions": [],
    "fetch_javadoc": False,
    "fetch_sources": False,
    "resolver": DEFAULT_RESOLVER,
    "strict_visibility": False,
    "strict_visibility_value": [],
    "aar_import_bzl_label": DEFAULT_AAR_IMPORT_LABEL,
    "use_starlark_android_rules": False,
    "additional_netrc_lines": [],
    "use_credentials_from_home_netrc_file": False,
    "duplicate_version_warning": "warn",
    "fail_if_repin_required": False,
    "lock_file": None,
    "repositories": DEFAULT_REPOSITORIES,
    "generate_compat_repositories": False,
    "excluded_artifacts": [],
    "fail_on_missing_checksum": True,
    "resolve_timeout": 600,
    "version_conflict_policy": "default",
    "ignore_empty_files": False,
    "repin_instructions": None,
    "additional_coursier_options": [],
    "override_targets": {},
    "errors": [],
}

_LIST_ATTRS = [
    "additional_coursier_options",
    "additional_netrc_lines",
    "artifacts",
    "boms",
    "excluded_artifacts",
    "exclusions",
    "repositories",
    "strict_visibility_value",
]

_BOOL_ATTRS = [
    "fetch_javadoc",
    "fetch_sources",
    "generate_compat_repositories",
]

_ERROR_ATTRS = [
    "aar_import_bzl_label",
    "duplicate_version_warning",
    "fail_if_repin_required",
    "fail_on_missing_checksum",
    "ignore_empty_files",
    "lock_file",
    "resolve_timeout",
    "resolver",
    "strict_visibility",
    "use_credentials_from_home_netrc_file",
    "use_starlark_android_rules",
    "version_conflict_policy",
]

def merge_install_tags(existing, to_add, to_add_is_from_root_module):
    to_return = {} | existing

    to_return["name"] = to_add["name"]

    for attribute in _LIST_ATTRS:
        to_return[attribute] = existing[attribute] + to_add[attribute]

    for attribute in _BOOL_ATTRS:
        to_return[attribute] = existing.get(attribute, False) or to_add.get(attribute, False)

    for attribute in _ERROR_ATTRS:
        set_but_error_if_different(
            attribute,
            _EMPTY_MODULE[attribute],
            to_return,
            to_add,
            to_add_is_from_root_module,
        )

    if to_add_is_from_root_module:
        to_return["repin_instructions"] = to_add["repin_instructions"]
    else:
        to_return["repin_instructions"] = None

    return to_return

def add_to_extension_deps(mctx, tag, direct_deps, direct_dev_deps):
    list = direct_deps if mctx.is_dev_dependency(tag) else direct_dev_deps
    if not tag.name in list:
        list.append(tag.name)

def maven_impl(mctx):
    name2params = {}

    root_modules = {}
    non_root_modules = {}
    direct_deps = []
    direct_dev_deps = []

    for mod in mctx.modules:
        collection = root_modules if mod.is_root else non_root_modules

        seen_names = []
        for install in mod.tags.install:
            if install.name in seen_names:
                fail("Only one `install` tag with the name", install.name, "can be declared in a single module file")
            seen_names.append(install.name)

            as_dict = structs.to_dict(install)
            as_dict["artifacts"] = explode(as_dict["artifacts"])
            as_dict["boms"] = explode(as_dict["boms"])
            as_dict["errors"] = []

            collection[install.name] = merge_install_tags(collection.get(install.name, _EMPTY_MODULE), as_dict, mod.is_root)

            add_to_extension_deps(mctx, install, direct_deps, direct_dev_deps)

        for artifact in mod.tags.artifact:
            params = collection.get(artifact.name, _EMPTY_MODULE)
            params["artifacts"] = params["artifacts"] + [
                struct(
                    group = artifact.group,
                    artifact = artifact.artifact,
                    version = artifact.version,
                    packaging = artifact.packaging,
                    classifier = artifact.classifier,
                    force_version = artifact.force_version,
                    neverlink = artifact.neverlink,
                    testonly = artifact.testonly,
                    exclusions = artifact.exclusions,
                ),
            ]
            collection[artifact.name] = params

            add_to_extension_deps(mctx, artifact, direct_deps, direct_dev_deps)

    for mod in (root_modules | non_root_modules).values():
        if len(mod["errors"]):
            msg = ("To avoid ambiguity, the maven repository `%s` needs to set the following attributes" +
                   " in an `install` tag in the root module: %s" % (mod["name"], ", ".join(mod["errors"])))
            fail(msg)
        if mod["lock_file"]:
            pass
        else:

    if bazel_features.external_deps.extension_metadata_has_reproducible:
        # The type and attributes of repositories created by this extension are fully deterministic
        # and thus don't need to be included in MODULE.bazel.lock.
        # Note: This ignores get_m2local_url, but that depends on local information and environment
        # variables only. In fact, since it depends on the host OS, *not* including the extension
        # result in the lockfile makes it more portable across different machines.
        return mctx.extension_metadata(
            root_module_direct_deps = direct_deps,
            root_module_direct_dev_deps = direct_dev_deps,
            reproducible = True,
        )
    else:
        return None

maven = module_extension(
    maven_impl,
    tag_classes = {
        "artifact": artifact_tag,
        "install": install_tag,
        "override": override_tag,
    },
)
