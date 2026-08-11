"""Tests for dependency layering across bzlmod modules."""

load("@bazel_skylib//lib:partial.bzl", "partial")
load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load(
    "//private/lib:layering.bzl",
    "deduplicate_non_root_artifacts",
    "merge_with_root_priority",
)

def _artifact(
        version,
        force_version = False,
        testonly = False,
        neverlink = False,
        exclusions = None,
        packaging = None,
        classifier = None):
    return struct(
        group = "com.example",
        artifact = "library",
        version = version,
        packaging = packaging,
        classifier = classifier,
        force_version = force_version,
        testonly = testonly,
        neverlink = neverlink,
        exclusions = exclusions or [],
    )

def _merge(root_artifacts, bazel_dep_to_non_root_artifacts):
    return merge_with_root_priority(
        "maven",
        root_artifacts,
        bazel_dep_to_non_root_artifacts,
        False,
        False,
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

    asserts.equals(env, [root, non_root], _merge([root], {"dep": [non_root]}))

    return unittest.end(env)

nonroot_higher_version_keeps_both_test = unittest.make(_nonroot_higher_version_keeps_both_impl)

def _nonroot_force_higher_survives_with_force_impl(ctx):
    env = unittest.begin(ctx)
    root = _artifact("1.0")
    non_root = _artifact("2.0", force_version = True)

    # A forced non-root declaration currently survives only when it is higher than the root.
    asserts.equals(env, [root, non_root], _merge([root], {"dep": [non_root]}))
    asserts.true(env, _merge([root], {"dep": [non_root]})[1].force_version)

    return unittest.end(env)

nonroot_force_higher_survives_with_force_test = unittest.make(_nonroot_force_higher_survives_with_force_impl)

def _nonroot_force_lower_is_silently_dropped_impl(ctx):
    env = unittest.begin(ctx)
    root = _artifact("2.0")

    # A lower forced non-root declaration is currently dropped without a diagnostic.
    asserts.equals(
        env,
        [root],
        _merge([root], {"dep": [_artifact("1.0", force_version = True)]}),
    )

    return unittest.end(env)

nonroot_force_lower_is_silently_dropped_test = unittest.make(_nonroot_force_lower_is_silently_dropped_impl)

def _nonroot_force_equal_loses_transitive_pin_impl(ctx):
    env = unittest.begin(ctx)
    root = _artifact("1.0")

    merged = _merge([root], {"dep": [_artifact("1.0", force_version = True)]})

    # An equal forced non-root declaration currently loses its transitive pin.
    asserts.equals(env, [root], merged)
    asserts.false(env, merged[0].force_version)

    return unittest.end(env)

nonroot_force_equal_loses_transitive_pin_test = unittest.make(_nonroot_force_equal_loses_transitive_pin_impl)

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

def layering_test_suite():
    unittest.suite(
        "layering_tests",
        partial.make(root_only_resolves_root_version_test, size = "small"),
        partial.make(nonroot_lower_version_is_dropped_test, size = "small"),
        partial.make(nonroot_higher_version_keeps_both_test, size = "small"),
        partial.make(nonroot_force_higher_survives_with_force_test, size = "small"),
        partial.make(nonroot_force_lower_is_silently_dropped_test, size = "small"),
        partial.make(nonroot_force_equal_loses_transitive_pin_test, size = "small"),
        partial.make(both_forced_root_wins_test, size = "small"),
        partial.make(single_nonroot_survives_test, size = "small"),
        partial.make(testonly_nonroot_is_filtered_test, size = "small"),
        partial.make(multiple_nonroot_highest_wins_test, size = "small"),
        partial.make(equal_version_tie_keeps_first_module_metadata_test, size = "small"),
        partial.make(root_force_beats_higher_unforced_nonroot_test, size = "small"),
        partial.make(conflicting_nonroot_forces_silently_pick_highest_test, size = "small"),
        partial.make(higher_unforced_nonroot_erases_force_test, size = "small"),
    )
