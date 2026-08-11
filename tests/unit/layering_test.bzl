"""Tests for dependency layering across bzlmod modules."""

load("@bazel_skylib//lib:new_sets.bzl", "sets")
load("@bazel_skylib//lib:partial.bzl", "partial")
load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load(
    "//private/lib:layering.bzl",
    "deduplicate_non_root_artifacts",
    "filter_known_contributing_modules",
    "layer_maven_namespace",
    "merge_with_root_priority",
    "should_print_diagnostic",
)

def _artifact(
        version,
        force_version = False,
        testonly = False,
        neverlink = False,
        exclusions = None,
        packaging = None,
        classifier = None,
        group = "com.example",
        artifact = "library"):
    return struct(
        group = group,
        artifact = artifact,
        version = version,
        packaging = packaging,
        classifier = classifier,
        force_version = force_version,
        testonly = testonly,
        neverlink = neverlink,
        exclusions = exclusions or [],
    )

def _merge_result(root_artifacts, bazel_dep_to_non_root_artifacts):
    return merge_with_root_priority(
        "maven",
        root_artifacts,
        bazel_dep_to_non_root_artifacts,
    )

def _merge(root_artifacts, bazel_dep_to_non_root_artifacts):
    return _merge_result(root_artifacts, bazel_dep_to_non_root_artifacts).artifacts

def _layer(
        name = "maven",
        root_present = True,
        root_artifacts = None,
        root_boms = None,
        resolver = "coursier",
        version_conflict_policy = "default",
        known_contributing_modules = None,
        non_root_artifacts = None,
        non_root_boms = None):
    return layer_maven_namespace(
        name = name,
        root_present = root_present,
        root_artifacts = root_artifacts or [],
        root_boms = root_boms or [],
        resolver = resolver,
        version_conflict_policy = version_conflict_policy,
        known_contributing_modules = known_contributing_modules or sets.make(),
        bazel_dep_to_non_root_artifacts = non_root_artifacts or {},
        bazel_dep_to_non_root_boms = non_root_boms or {},
    )

def _root_only_resolves_root_version_impl(ctx):
    env = unittest.begin(ctx)
    root = _artifact("1.0")

    asserts.equals(env, [root], _merge([root], {}))

    return unittest.end(env)

root_only_resolves_root_version_test = unittest.make(_root_only_resolves_root_version_impl)

def _nonroot_lower_version_is_dropped_impl(ctx):
    env = unittest.begin(ctx)
    root = _artifact("2.0")

    asserts.equals(env, [root], _merge([root], {"dep": [_artifact("1.0")]}))

    return unittest.end(env)

nonroot_lower_version_is_dropped_test = unittest.make(_nonroot_lower_version_is_dropped_impl)

def _nonroot_higher_version_keeps_both_impl(ctx):
    env = unittest.begin(ctx)
    root = _artifact("1.0")
    non_root = _artifact("2.0")

    result = _merge_result([root], {"dep": [non_root]})

    asserts.equals(env, [root, non_root], result.artifacts)
    asserts.equals(
        env,
        [struct(
            text = "\nWARNING: For dependency 'com.example:library' the root @maven repo wants version 1.0, but got 2.0 from the dep bazel dep. Please update the version in your MODULE.bazel or set `force_version = True`.",
            gate = "repin",
        )],
        result.diagnostics,
    )

    return unittest.end(env)

nonroot_higher_version_keeps_both_test = unittest.make(_nonroot_higher_version_keeps_both_impl)

def _higher_nonroot_force_beats_unforced_root_impl(ctx):
    env = unittest.begin(ctx)
    root = _artifact("1.0")
    non_root = _artifact("2.0", force_version = True)

    result = _merge_result([root], {"dep": [non_root]})

    asserts.equals(env, [non_root], result.artifacts)
    asserts.true(env, result.artifacts[0].force_version)
    asserts.equals(env, "repin", result.diagnostics[0].gate)

    return unittest.end(env)

higher_nonroot_force_beats_unforced_root_test = unittest.make(_higher_nonroot_force_beats_unforced_root_impl)

def _lower_nonroot_force_beats_unforced_root_impl(ctx):
    env = unittest.begin(ctx)
    root = _artifact("2.0")
    non_root = _artifact("1.0", force_version = True)

    result = _merge_result([root], {"dep": [non_root]})

    asserts.equals(env, [non_root], result.artifacts)
    asserts.equals(env, "repin", result.diagnostics[0].gate)

    return unittest.end(env)

lower_nonroot_force_beats_unforced_root_test = unittest.make(_lower_nonroot_force_beats_unforced_root_impl)

def _equal_nonroot_force_retains_transitive_pin_impl(ctx):
    env = unittest.begin(ctx)
    root = _artifact("1.0")
    non_root = _artifact("1.0", force_version = True)

    result = _merge_result([root], {"dep": [non_root]})

    asserts.equals(env, [non_root], result.artifacts)
    asserts.true(env, result.artifacts[0].force_version)
    asserts.equals(env, [], result.diagnostics)

    return unittest.end(env)

equal_nonroot_force_retains_transitive_pin_test = unittest.make(_equal_nonroot_force_retains_transitive_pin_impl)

def _both_forced_root_wins_impl(ctx):
    env = unittest.begin(ctx)
    root = _artifact("1.0", force_version = True)

    asserts.equals(
        env,
        [root],
        _merge([root], {"dep": [_artifact("2.0", force_version = True)]}),
    )

    return unittest.end(env)

both_forced_root_wins_test = unittest.make(_both_forced_root_wins_impl)

def _single_nonroot_survives_impl(ctx):
    env = unittest.begin(ctx)
    non_root = _artifact("1.0")

    asserts.equals(
        env,
        [non_root],
        deduplicate_non_root_artifacts({"dep": [non_root]}, return_only_artifacts = True),
    )

    return unittest.end(env)

single_nonroot_survives_test = unittest.make(_single_nonroot_survives_impl)

def _testonly_nonroot_is_filtered_impl(ctx):
    env = unittest.begin(ctx)

    asserts.equals(
        env,
        [],
        deduplicate_non_root_artifacts(
            {"dep": [_artifact("1.0", testonly = True)]},
            return_only_artifacts = True,
        ),
    )

    return unittest.end(env)

testonly_nonroot_is_filtered_test = unittest.make(_testonly_nonroot_is_filtered_impl)

def _multiple_nonroot_highest_wins_impl(ctx):
    env = unittest.begin(ctx)
    higher = _artifact("2.0")

    asserts.equals(
        env,
        [higher],
        deduplicate_non_root_artifacts(
            {"first": [_artifact("1.0")], "second": [higher]},
            return_only_artifacts = True,
        ),
    )

    return unittest.end(env)

multiple_nonroot_highest_wins_test = unittest.make(_multiple_nonroot_highest_wins_impl)

def _equal_version_tie_keeps_first_module_metadata_impl(ctx):
    env = unittest.begin(ctx)
    first = _artifact(
        "1.0",
        force_version = True,
        neverlink = True,
        exclusions = [struct(group = "excluded", artifact = "first")],
    )
    second = _artifact(
        "1.0",
        exclusions = [struct(group = "excluded", artifact = "second")],
    )

    asserts.equals(
        env,
        [first],
        deduplicate_non_root_artifacts(
            {"first": [first], "second": [second]},
            return_only_artifacts = True,
        ),
    )

    return unittest.end(env)

equal_version_tie_keeps_first_module_metadata_test = unittest.make(_equal_version_tie_keeps_first_module_metadata_impl)

def _root_force_beats_higher_unforced_nonroot_impl(ctx):
    env = unittest.begin(ctx)
    root = _artifact("1.0", force_version = True)

    asserts.equals(env, [root], _merge([root], {"dep": [_artifact("2.0")]}))

    return unittest.end(env)

root_force_beats_higher_unforced_nonroot_test = unittest.make(_root_force_beats_higher_unforced_nonroot_impl)

def _conflicting_nonroot_forces_silently_pick_highest_impl(ctx):
    env = unittest.begin(ctx)
    higher = _artifact("2.0", force_version = True)

    # Conflicting non-root forces currently resolve without a diagnostic.
    asserts.equals(
        env,
        [higher],
        deduplicate_non_root_artifacts(
            {
                "first": [_artifact("1.0", force_version = True)],
                "second": [higher],
            },
            return_only_artifacts = True,
        ),
    )

    return unittest.end(env)

conflicting_nonroot_forces_silently_pick_highest_test = unittest.make(_conflicting_nonroot_forces_silently_pick_highest_impl)

def _higher_unforced_nonroot_erases_force_impl(ctx):
    env = unittest.begin(ctx)
    higher = _artifact("2.0")

    # The highest declaration currently wins without preserving another module's force.
    asserts.equals(
        env,
        [higher],
        deduplicate_non_root_artifacts(
            {
                "first": [_artifact("1.0", force_version = True)],
                "second": [higher],
            },
            return_only_artifacts = True,
        ),
    )

    return unittest.end(env)

higher_unforced_nonroot_erases_force_test = unittest.make(_higher_unforced_nonroot_erases_force_impl)

def _namespace_without_root_uses_nonroot_dedup_impl(ctx):
    env = unittest.begin(ctx)
    higher = _artifact("2.0")

    result = _layer(
        root_present = False,
        non_root_artifacts = {
            "first": [_artifact("1.0")],
            "second": [higher],
        },
    )

    asserts.equals(env, [higher], result.artifacts)
    asserts.equals(env, [], result.boms)
    asserts.equals(env, [], result.diagnostics)

    return unittest.end(env)

namespace_without_root_uses_nonroot_dedup_test = unittest.make(_namespace_without_root_uses_nonroot_dedup_impl)

def _known_contributors_filter_deps_and_boms_impl(ctx):
    env = unittest.begin(ctx)
    kept_artifact = _artifact("1.0")
    kept_bom = _artifact("1.0", packaging = "pom", artifact = "bom")

    artifacts = filter_known_contributing_modules(
        "custom",
        sets.make(["kept"]),
        {"kept": [kept_artifact], "excluded-dep": [_artifact("2.0")]},
        "deps",
    )
    boms = filter_known_contributing_modules(
        "custom",
        sets.make(["kept"]),
        {"kept": [kept_bom], "excluded-bom": [_artifact("2.0", packaging = "pom", artifact = "bom")]},
        "boms",
    )

    asserts.equals(env, {"kept": [kept_artifact]}, artifacts.filtered)
    asserts.equals(env, {"kept": [kept_bom]}, boms.filtered)
    asserts.equals(
        env,
        [struct(
            text = "\nINFO: The @custom repo is not using deps from excluded-dep because it is not in the known_contributing_modules",
            gate = "verbose",
        )],
        artifacts.diagnostics,
    )
    asserts.equals(
        env,
        [struct(
            text = "\nINFO: The @custom repo is not using boms from excluded-bom because it is not in the known_contributing_modules",
            gate = "verbose",
        )],
        boms.diagnostics,
    )

    return unittest.end(env)

known_contributors_filter_deps_and_boms_test = unittest.make(_known_contributors_filter_deps_and_boms_impl)

def _bom_only_contributor_does_not_warn_about_modules_impl(ctx):
    env = unittest.begin(ctx)
    bom = _artifact("1.0", packaging = "pom", artifact = "bom")

    result = _layer(non_root_boms = {"dep": [bom]})

    asserts.equals(env, [bom], result.boms)
    asserts.equals(
        env,
        [struct(
            text = "\nINFO: The @maven repo is getting the additional artifact com.example:bom:1.0 from the dep bazel dep.",
            gate = "repin_verbose",
        )],
        result.diagnostics,
    )

    return unittest.end(env)

bom_only_contributor_does_not_warn_about_modules_test = unittest.make(_bom_only_contributor_does_not_warn_about_modules_impl)

def _boms_merge_with_root_priority_impl(ctx):
    env = unittest.begin(ctx)
    root = _artifact("1.0", packaging = "pom", artifact = "bom", force_version = True)

    result = _layer(
        root_boms = [root],
        non_root_boms = {"dep": [_artifact("2.0", packaging = "pom", artifact = "bom")]},
    )

    asserts.equals(env, [root], result.boms)

    return unittest.end(env)

boms_merge_with_root_priority_test = unittest.make(_boms_merge_with_root_priority_impl)

def _classifier_and_packaging_layer_independently_impl(ctx):
    env = unittest.begin(ctx)
    plain = _artifact("1.0")
    classified = _artifact("2.0", classifier = "tests")
    pom = _artifact("3.0", packaging = "pom")

    result = _layer(
        root_present = False,
        non_root_artifacts = {"dep": [plain, classified, pom]},
    )

    asserts.equals(env, [plain, classified, pom], result.artifacts)

    return unittest.end(env)

classifier_and_packaging_layer_independently_test = unittest.make(_classifier_and_packaging_layer_independently_impl)

def _pinned_gradle_root_beats_higher_nonroot_force_impl(ctx):
    env = unittest.begin(ctx)
    root = _artifact("1.0")

    result = _layer(
        root_artifacts = [root],
        resolver = "gradle",
        version_conflict_policy = "pinned",
        non_root_artifacts = {"dep": [_artifact("2.0", force_version = True)]},
    )

    asserts.equals(env, ["1.0"], [artifact.version for artifact in result.artifacts])
    asserts.true(env, result.artifacts[0].force_version)

    return unittest.end(env)

pinned_gradle_root_beats_higher_nonroot_force_test = unittest.make(_pinned_gradle_root_beats_higher_nonroot_force_impl)

def _namespaces_are_layered_independently_impl(ctx):
    env = unittest.begin(ctx)

    first = _layer(
        name = "first",
        root_present = False,
        non_root_artifacts = {"dep": [_artifact("1.0")]},
    )
    second = _layer(
        name = "second",
        root_present = False,
        non_root_artifacts = {"dep": [_artifact("2.0")]},
    )

    asserts.equals(env, ["1.0"], [artifact.version for artifact in first.artifacts])
    asserts.equals(env, ["2.0"], [artifact.version for artifact in second.artifacts])

    return unittest.end(env)

namespaces_are_layered_independently_test = unittest.make(_namespaces_are_layered_independently_impl)

def _diagnostics_preserve_text_gates_and_order_impl(ctx):
    env = unittest.begin(ctx)
    root_artifact = _artifact("1.0")
    root_bom = _artifact("1.0", packaging = "pom", artifact = "bom")
    kept_artifacts = [
        _artifact("2.0"),
        _artifact("1.0", artifact = "additional"),
    ]
    kept_boms = [
        _artifact("2.0", packaging = "pom", artifact = "bom"),
        _artifact("1.0", packaging = "pom", artifact = "additional-bom"),
    ]

    result = _layer(
        name = "custom",
        root_artifacts = [root_artifact],
        root_boms = [root_bom],
        known_contributing_modules = sets.make(["kept"]),
        non_root_artifacts = {
            "kept": kept_artifacts,
            "excluded-dep": [_artifact("3.0")],
        },
        non_root_boms = {
            "kept": kept_boms,
            "excluded-bom": [_artifact("3.0", packaging = "pom", artifact = "bom")],
        },
    )

    asserts.equals(
        env,
        [
            struct(text = "\nINFO: The @custom repo is not using deps from excluded-dep because it is not in the known_contributing_modules", gate = "verbose"),
            struct(text = "\nINFO: The @custom repo is not using boms from excluded-bom because it is not in the known_contributing_modules", gate = "verbose"),
            struct(text = "\nWARNING: For dependency 'com.example:library' the root @custom repo wants version 1.0, but got 2.0 from the kept bazel dep. Please update the version in your MODULE.bazel or set `force_version = True`.", gate = "repin"),
            struct(text = "\nINFO: The @custom repo is getting the additional artifact com.example:additional:1.0 from the kept bazel dep.", gate = "repin_verbose"),
            struct(text = "\nWARNING: For dependency 'com.example:bom' the root @custom repo wants version 1.0, but got 2.0 from the kept bazel dep. Please update the version in your MODULE.bazel or set `force_version = True`.", gate = "repin"),
            struct(text = "\nINFO: The @custom repo is getting the additional artifact com.example:additional-bom:1.0 from the kept bazel dep.", gate = "repin_verbose"),
        ],
        result.diagnostics,
    )

    return unittest.end(env)

diagnostics_preserve_text_gates_and_order_test = unittest.make(_diagnostics_preserve_text_gates_and_order_impl)

def _default_namespace_contribution_warning_is_preserved_impl(ctx):
    env = unittest.begin(ctx)

    result = _layer(non_root_artifacts = {"dep": [_artifact("1.0")]})

    asserts.equals(
        env,
        [struct(
            text = "The maven repository 'maven' has contributions from multiple bzlmod modules, and will be resolved together: [\"dep\"].\nSee https://github.com/bazel-contrib/rules_jvm_external/blob/master/docs/bzlmod.md#module-dependency-layering for more information. \n To suppress this warning review the contributions from the other modules and add the following attribute in the root MODULE.bazel file: \nmaven.install(\n  known_contributing_modules = [\"dep\"],\n  ...\n)",
            gate = "always",
        ), struct(
            text = "\nINFO: The @maven repo is getting the additional artifact com.example:library:1.0 from the dep bazel dep.",
            gate = "repin_verbose",
        )],
        result.diagnostics,
    )

    return unittest.end(env)

default_namespace_contribution_warning_is_preserved_test = unittest.make(_default_namespace_contribution_warning_is_preserved_impl)

def _diagnostic_gates_match_environment_flags_impl(ctx):
    env = unittest.begin(ctx)
    diagnostics = {
        gate: struct(text = gate, gate = gate)
        for gate in ["always", "repin", "verbose", "repin_verbose"]
    }

    asserts.equals(
        env,
        [True, False, False, False],
        [should_print_diagnostic(diagnostics[gate], False, False) for gate in diagnostics],
    )
    asserts.equals(
        env,
        [True, True, False, False],
        [should_print_diagnostic(diagnostics[gate], True, False) for gate in diagnostics],
    )
    asserts.equals(
        env,
        [True, False, True, False],
        [should_print_diagnostic(diagnostics[gate], False, True) for gate in diagnostics],
    )
    asserts.equals(
        env,
        [True, True, True, True],
        [should_print_diagnostic(diagnostics[gate], True, True) for gate in diagnostics],
    )

    return unittest.end(env)

diagnostic_gates_match_environment_flags_test = unittest.make(_diagnostic_gates_match_environment_flags_impl)

def layering_test_suite():
    unittest.suite(
        "layering_tests",
        partial.make(root_only_resolves_root_version_test, size = "small"),
        partial.make(nonroot_lower_version_is_dropped_test, size = "small"),
        partial.make(nonroot_higher_version_keeps_both_test, size = "small"),
        partial.make(higher_nonroot_force_beats_unforced_root_test, size = "small"),
        partial.make(lower_nonroot_force_beats_unforced_root_test, size = "small"),
        partial.make(equal_nonroot_force_retains_transitive_pin_test, size = "small"),
        partial.make(both_forced_root_wins_test, size = "small"),
        partial.make(single_nonroot_survives_test, size = "small"),
        partial.make(testonly_nonroot_is_filtered_test, size = "small"),
        partial.make(multiple_nonroot_highest_wins_test, size = "small"),
        partial.make(equal_version_tie_keeps_first_module_metadata_test, size = "small"),
        partial.make(root_force_beats_higher_unforced_nonroot_test, size = "small"),
        partial.make(conflicting_nonroot_forces_silently_pick_highest_test, size = "small"),
        partial.make(higher_unforced_nonroot_erases_force_test, size = "small"),
        partial.make(namespace_without_root_uses_nonroot_dedup_test, size = "small"),
        partial.make(known_contributors_filter_deps_and_boms_test, size = "small"),
        partial.make(bom_only_contributor_does_not_warn_about_modules_test, size = "small"),
        partial.make(boms_merge_with_root_priority_test, size = "small"),
        partial.make(classifier_and_packaging_layer_independently_test, size = "small"),
        partial.make(pinned_gradle_root_beats_higher_nonroot_force_test, size = "small"),
        partial.make(namespaces_are_layered_independently_test, size = "small"),
        partial.make(diagnostics_preserve_text_gates_and_order_test, size = "small"),
        partial.make(default_namespace_contribution_warning_is_preserved_test, size = "small"),
        partial.make(diagnostic_gates_match_environment_flags_test, size = "small"),
    )
