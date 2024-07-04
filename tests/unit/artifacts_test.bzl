load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//private/lib:artifacts.bzl", "artifacts")

ALL_TESTS = []

def add_test(test_impl_func):
    test = unittest.make(test_impl_func)
    ALL_TESTS.append(test)
    return test

def _artifact_list_is_empty_test_impl(ctx):
    env = unittest.begin(ctx)

    a = artifacts.new()

    asserts.equals(
        env,
        0,
        len(artifacts.to_list(a)),
    )
    return unittest.end(env)

artifact_list_is_empty_test = add_test(_artifact_list_is_empty_test_impl)

def _add_single_coordinate_to_list(ctx):
    env = unittest.begin(ctx)

    a = artifacts.new()
    artifacts.add(a, "com:example:1.0")

    asserts.equals(
        env,
        [{"group": "com", "artifact": "example", "version": "1.0"}],
        artifacts.to_list(a),
    )

    return unittest.end(env)

add_single_coordinate_test = add_test(_add_single_coordinate_to_list)

def _added_artifacts_should_be_sorted(ctx):
    env = unittest.begin(ctx)

    a = artifacts.new()
    artifacts.add(a, "com:beta:1.0")
    artifacts.add(a, "com:alpha:1.0")
    artifacts.add(a, "com:gamma:3.0")
    artifacts.add(a, "com:gamma")
    artifacts.add(a, "com:gamma:1.0")
    artifacts.add(a, "com:gamma:2.0")

    asserts.equals(
        env,
        [{"group": "com", "artifact": "example", "version": "1.0"}],
        artifacts.to_list(a),
    )

    return unittest.end(env)

added_artifacts_should_be_sorted_test = add_test(_added_artifacts_should_be_sorted)

def artifacts_test_suite():
    unittest.suite(
        "artifact_tests",
        *ALL_TESTS
    )
