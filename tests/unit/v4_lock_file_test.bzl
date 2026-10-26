load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts", "unittest")
load("//private/rules:lock_file_inputs.bzl", "canonical_inputs")
load("//private/rules:v4_lock_file.bzl", "v4_lock_file")

def _legacy():
    return {
        "artifacts": {"g:a": {"version": "2", "shasums": {"jar": "a" * 64, "sources": None}}},
        "dependencies": {},
        "repositories": {"repo/": ["g:a", "g:a:jar:sources"]},
        "services": {},
        "skipped": ["g:a:jar:sources"],
    }

def _compact_records_round_trip_inputs_and_keep_merge_separators_impl(ctx):
    env = unittest.begin(ctx)
    inputs = canonical_inputs(artifacts = [{"group": "g", "artifact": "a", "version": "1"}])
    text = v4_lock_file.render_lock_file(_legacy(), inputs)
    lock = json.decode(text)
    asserts.true(env, v4_lock_file.is_valid_lock_file(lock))
    asserts.false(env, "__INPUT_ARTIFACTS_HASH" in lock)
    asserts.false(env, "__RESOLVED_ARTIFACTS_HASH" in lock)
    asserts.true(env, "],\n\n    [" in text)
    asserts.equals(env, inputs, v4_lock_file.get_inputs(lock))
    asserts.equals(env, v4_lock_file.get_lock_file_hash(lock), v4_lock_file.compute_lock_file_hash(lock))
    original = lock["artifacts"][0][2]
    lock["repositories"] = {"mirror/": ["g:a"]}
    asserts.equals(env, original, v4_lock_file.compute_lock_file_hash(lock)["g:a"])
    lock["artifacts"].pop()
    asserts.true(env, v4_lock_file.get_lock_file_hash(lock) != v4_lock_file.compute_lock_file_hash(lock))
    return unittest.end(env)

compact_records_round_trip_inputs_and_keep_merge_separators_test = unittest.make(_compact_records_round_trip_inputs_and_keep_merge_separators_impl)

def _bom_only_and_unselected_requests_are_retained_impl(ctx):
    env = unittest.begin(ctx)
    request = {"group": "g", "artifact": "missing", "version": ""}
    boms = [{"group": "g", "artifact": "bom", "version": "2"}, {"group": "g", "artifact": "bom", "version": "1"}]
    original = _legacy()
    original["artifacts"] = {}
    original["skipped"] = []
    inputs = canonical_inputs(artifacts = [request], boms = boms)
    lock = json.decode(v4_lock_file.render_lock_file(original, inputs))
    asserts.equals(env, boms, lock["boms"])
    asserts.equals(env, [request], lock["unresolved_requests"])
    asserts.equals(env, inputs, v4_lock_file.get_inputs(lock))
    for key in ["boms", "settings", "unresolved_requests"]:
        copy = dict(lock)
        copy.pop(key)
        asserts.false(env, v4_lock_file.is_valid_lock_file(copy))
    return unittest.end(env)

bom_only_and_unselected_requests_are_retained_test = unittest.make(_bom_only_and_unselected_requests_are_retained_impl)

def _classified_named_versions_reach_legacy_consumers_unambiguously_impl(ctx):
    env = unittest.begin(ctx)
    lock = _legacy()
    lock["artifacts"]["g:a"]["version"] = "RELEASE"
    pinned = json.decode(v4_lock_file.render_lock_file(lock, canonical_inputs()))
    artifacts = v4_lock_file.get_artifacts(pinned)
    asserts.equals(env, "g:a:jar:sources:RELEASE", artifacts[1]["coordinates"])
    return unittest.end(env)

classified_named_versions_reach_legacy_consumers_unambiguously_test = unittest.make(_classified_named_versions_reach_legacy_consumers_unambiguously_impl)

def _legacy_identity_aliases_are_canonicalised_impl(ctx):
    env = unittest.begin(ctx)
    lock = _legacy()
    lock["m2local"] = True
    lock["repositories"] = {"repo/": ["g:a:jar", "g:a:jar:sources"]}
    lock["skipped"] = ["g:a:jar:sources", "g:a:jar"]
    lock["dependencies"] = {"g:a:jar": ["g:a:jar:sources"]}
    converted = json.decode(v4_lock_file.render_lock_file(lock, canonical_inputs()))
    asserts.equals(env, "a" * 64, converted["artifacts"][0][1])
    asserts.equals(env, [], converted["m2local_artifacts"])
    asserts.equals(env, ["g:a", "g:a:jar:sources"], converted["skipped"])
    asserts.equals(env, {"g:a": ["g:a:jar:sources"]}, converted["dependencies"])
    return unittest.end(env)

legacy_identity_aliases_are_canonicalised_test = unittest.make(_legacy_identity_aliases_are_canonicalised_impl)

def _render_invalid_graph_impl(ctx):
    lock = _legacy()
    if ctx.attr.duplicate:
        lock["artifacts"]["g:a:jar"] = {"version": "2", "shasums": {"jar": "a" * 64}}
    else:
        lock["dependencies"] = {"g:a": ["g:missing"]}
    v4_lock_file.render_lock_file(lock, canonical_inputs())
    return []

_render_invalid_graph = rule(implementation = _render_invalid_graph_impl, attrs = {"duplicate": attr.bool()})

def _invalid_graph_is_not_written_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, ctx.attr.message)
    return analysistest.end(env)

_invalid_graph_is_not_written_test = analysistest.make(_invalid_graph_is_not_written_impl, expect_failure = True, attrs = {"message": attr.string(default = "Cannot pin lock file with missing dependencies")})

def v4_lock_file_test_suite():
    unittest.suite(
        "v4_lock_file_tests",
        compact_records_round_trip_inputs_and_keep_merge_separators_test,
        bom_only_and_unselected_requests_are_retained_test,
        classified_named_versions_reach_legacy_consumers_unambiguously_test,
        legacy_identity_aliases_are_canonicalised_test,
    )
    _render_invalid_graph(name = "render_invalid_graph", tags = ["manual"])
    _invalid_graph_is_not_written_test(name = "invalid_graph_is_not_written_test", target_under_test = ":render_invalid_graph")

    _render_invalid_graph(name = "render_duplicate_identity", duplicate = True, tags = ["manual"])
    _invalid_graph_is_not_written_test(name = "duplicate_identity_is_not_written_test", target_under_test = ":render_duplicate_identity", message = "Duplicate artifact identity")
