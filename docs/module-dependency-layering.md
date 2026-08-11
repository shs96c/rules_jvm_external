# Module dependency layering

The extension collects declarations from all tags with the same `name` before resolving them. Each
name is an independent Maven repository namespace. Declarations in one namespace never affect
another namespace.

The root module and its dependencies have different roles during layering. The root contributes
the declarations that belong to the current Bazel project. Every other module is a non-root
contributor. Coordinates are matched by `group:artifact`, with non-default packaging and classifiers
included in the key. For example, a classified JAR layers independently of its unclassified JAR.

## Version precedence

The current layering rules are:

| # | Declarations for one coordinate | Layering behaviour |
|---|---|---|
| 1 | Root only | The root declaration is retained. |
| 2 | Root and non-root, with no `force_version` | A lower or equal non-root declaration is discarded. A higher non-root declaration is retained alongside the root declaration and the resolver chooses between them. Coursier and Gradle choose the highest version, while the Maven resolver chooses the root version because it uses the first direct declaration and root declarations are first. `duplicate_version_warning = "error"` fails before resolution when both versions survive. |
| 3 | Unforced root and forced non-root | The non-root declaration is retained and the root declaration is discarded, regardless of version. An equal non-root declaration therefore retains its pin against a transitive upgrade. |
| 4 | Forced root and forced non-root | The root declaration is retained and the non-root declaration is discarded. |
| 5 | One non-root module only | Its declaration is retained. A non-root artifact marked `testonly` is filtered out. |
| 6 | Multiple non-root modules, with no force | The highest version is retained. Equal versions keep the first module's complete declaration, including exclusions and flags. |
| 7 | Forced root and unforced non-root | The root declaration is retained, regardless of version. |
| 8 | Multiple non-root modules force different versions, and the root does not force that coordinate | Layering fails before resolution. The error identifies both contributing modules and versions, and tells the user to declare the wanted version in the root module with `force_version = True`. |

A single forced non-root declaration still participates in highest-version deduplication with other
non-root declarations. A higher unforced declaration can replace it and remove the force.

"Highest" uses the Maven `ComparableVersion` ordering implemented by
[`private/rules/maven_version.bzl`](../private/rules/maven_version.bzl), not lexical string ordering. Non-root deduplication uses this
ordering before declarations are compared with the root.

Rule 2 is resolver-dependent because the extension passes both declarations to the resolver when
the non-root version is higher. Coursier uses its default highest-version reconciliation. Gradle
also selects the highest version. The Maven resolver normalises duplicate direct
`group:artifact` declarations to the first version, which is the root version.

`version_conflict_policy = "pinned"` changes this interaction. For the Gradle and Maven resolvers,
root artifacts are force-marked before layering, so the root wins even against a higher forced
non-root declaration. For Coursier, the layering step is unchanged and every surviving direct
version is later passed as a `--force-version` argument.

The `force_version` flag can be set by an `artifact` tag, an `amend_artifact` tag, or a regular
artifact read by `from_toml`. Coordinates in `install.artifacts` cannot carry the flag. BOMs use the
same extension-layer precedence rules as artifacts, but a BOM can only gain `force_version` through
`amend_artifact`. A TOML BOM is returned before the TOML force field is copied. Resolver requests do
not propagate a BOM force flag, so it affects extension-layer priority only.

## Contributors and configuration

When the root and other modules contribute artifacts to the same namespace, the extension prints a
message such as:

`The maven repository 'multiple_lock_files' has contributions from multiple bzlmod modules, and will be resolved together: ["bzlmod_lock_files", "rules_jvm_external"]`

If those contributions are expected, set `known_contributing_modules` on the root `install` tag.
The warning includes the value to add. Once this attribute is non-empty, only listed modules may
contribute artifacts or BOMs to that namespace. A module that contributes only BOMs does not trigger
the contribution warning.

After dependencies are layered, scalar `install` attributes from the root module take precedence.
List attributes are combined root-first, while preserving their existing deduplication or
concatenation behaviour.

The default namespace is `maven`. A module intended for use through `bazel_dep` should normally use
its own name, such as the `rules_jvm_external_deps` namespace used by this project. The default is
appropriate when a module deliberately contributes functionality that would otherwise be supplied
as a Maven dependency, or when the project is only used as the root module.

## Diagnostics

Layering keeps the following diagnostics so that unexpected versions can be traced to their
contributing module:

| Condition | Behaviour |
|---|---|
| An unacknowledged non-root module contributes artifacts | Always prints the contribution warning. |
| Non-root modules force different versions of a coordinate that the root does not force | Fails with the contributing module names and versions, and tells the user how to select a version in the root module. |
| `known_contributing_modules` excludes an artifact or BOM contributor | Prints an `INFO` message when `RJE_VERBOSE` is set. |
| A higher unforced non-root version survives alongside the root version, or a differently versioned forced non-root replaces it | Prints the root-version warning when `REPIN` or `RULES_JVM_EXTERNAL_REPIN` is set. |
| A non-root-only coordinate is added | Prints an `INFO` message when a repin variable and `RJE_VERBOSE` are both set. |
| Multiple versions reach the repository rule | `duplicate_version_warning` controls whether to warn, fail, or do nothing. Its default is `warn`. |

The repository-level duplicate check keys declarations by `group:artifact` and optional classifier,
but not packaging. Packaging-distinct declarations at different versions can therefore warn or fail
even though the extension layers them independently.

For example, the root-version warning is:

```
WARNING: For dependency 'com.google.protobuf:protobuf-java' the root @maven repo wants version 3.25.5, but got 4.27.2 from the bazel_worker_java bazel dep. Please update the version in your MODULE.bazel or set `force_version = True`.
```
