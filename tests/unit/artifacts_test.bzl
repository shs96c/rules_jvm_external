load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//:specs.bzl", "maven")
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

def _can_populate_artifacts_from_arguments_of_workspace_based_maven_install(ctx):
    env = unittest.begin(ctx)

    from_workspace = [
        "com.example:foo:1.0.0",
        maven.artifact(
            artifact = "guava",
            exclusions = [
                maven.exclusion(
                    artifact = "animal-sniffer-annotations",
                    group = "org.codehaus.mojo",
                ),
                "com.google.j2objc:j2objc-annotations",
            ],
            group = "com.google.guava",
            version = "27.0-jre",
        ),
    ]
    a = artifacts.new(from_workspace)

    asserts.equals(
        env,
        [
            {"group": "com.example", "artifact": "foo", "version": "1.0.0"},
            {"group": "com.google.guava", "artifact": "guava", "version": "27.0-jre", "exclusions": ["com.google.j2objc:j2objc-annotations", "org.codehaus.mojo:animal-sniffer-annotations"]},
        ],
        artifacts.to_list(a),
    )

    return unittest.end(env)

can_populate_artifacts_from_arguments_of_workspace_based_maven_install_test = add_test(_can_populate_artifacts_from_arguments_of_workspace_based_maven_install)

def _can_populate_artifacts_from_arguments_of_bazlmod_install_tags(ctx):
    env = unittest.begin(ctx)

    from_tags = [
        "com.example:foo:1.0.0",  # as if from maven.install
        struct(
            # as if from maven.artifact
            group = "com.google.guava",
            artifact = "guava",
            version = "27.0-jre",
            exclusions = [
                "org.codehaus.mojo:animal-sniffer-annotations",
                "com.google.j2objc:j2objc-annotations",
            ],
        ),
    ]
    a = artifacts.new(from_tags)

    [
        {"group": "com.example", "artifact": "foo", "version": "1.0.0"},
        {"group": "com.example", "artifact": "foo", "version": "1.0.0"},
        {"group": "com.google.guava", "artifact": "guava", "version": "27.0-jre", "exclusions": ["com.google.j2objc:j2objc-annotations", "org.codehaus.mojo:animal-sniffer-annotations"]},
        {"group": "com.google.guava", "artifact": "guava", "version": "27.0-jre", "exclusions": ["animal-sniffer-annotations:org.codehaus.mojo", "com.google.j2objc:j2objc-annotations"]},
    ]

    asserts.equals(
        env,
        [
            {"group": "com.example", "artifact": "foo", "version": "1.0.0"},
            {"group": "com.google.guava", "artifact": "guava", "version": "27.0-jre", "exclusions": ["com.google.j2objc:j2objc-annotations", "org.codehaus.mojo:animal-sniffer-annotations"]},
        ],
        artifacts.to_list(a),
    )

    return unittest.end(env)

can_populate_artifacts_from_arguments_of_bazlmod_install_tags_test = add_test(_can_populate_artifacts_from_arguments_of_bazlmod_install_tags)

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
        [
            {"group": "com", "artifact": "alpha", "version": "1.0"},
            {"group": "com", "artifact": "beta", "version": "1.0"},
            {"group": "com", "artifact": "gamma"},
            {"group": "com", "artifact": "gamma", "version": "1.0"},
            {"group": "com", "artifact": "gamma", "version": "2.0"},
            {"group": "com", "artifact": "gamma", "version": "3.0"},
        ],
        artifacts.to_list(a),
    )

    return unittest.end(env)

added_artifacts_should_be_sorted_test = add_test(_added_artifacts_should_be_sorted)

def _should_select_most_recently_added_artifact(ctx):
    env = unittest.begin(ctx)

    a = artifacts.new()
    artifacts.add(a, {"group": "com", "artifact": "example", "neverlink": True})
    artifacts.add(a, {"group": "com", "artifact": "example", "testonly": True})

    asserts.equals(
        env,
        [{"group": "com", "artifact": "example", "testonly": True}],
        artifacts.to_list(a),
    )

    return unittest.end(env)

should_select_most_recently_added_artifact_test = add_test(_should_select_most_recently_added_artifact)

def artifacts_test_suite():
    unittest.suite(
        "artifact_tests",
        *ALL_TESTS
    )
