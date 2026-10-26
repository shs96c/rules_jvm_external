// Copyright 2026 The Bazel Authors. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package com.github.bazelbuild.rules_jvm_external.resolver.lockfile;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.junit.Test;

public class V4ArtifactsTest {
  @Test
  public void shouldRetainAllClassifiersIncludingNullChecksums() {
    Map<String, Object> sums = new HashMap<>();
    sums.put("jar", "sha");
    sums.put("sources", null);
    V4Artifacts result =
        new V4Artifacts(
            Map.of("artifacts", Map.of("g:a:aar", Map.of("version", "2", "shasums", sums))));
    assertEquals(Set.of("g:a:aar", "g:a:aar:sources"), result.byIdentity.keySet());
    assertEquals("g:a:2:sources@aar", result.byIdentity.get("g:a:aar:sources").externalForm());
  }

  @Test
  public void shouldRejectDuplicateIdentities() {
    invalid(
        () ->
            new V4Artifacts(
                Map.of("artifacts", Map.of("g:a", artifact("1"), "g:a:jar", artifact("1")))));
  }

  @Test
  public void shouldRejectMissingDependencyParentsAndChildren() {
    Map<String, Object> data = new HashMap<>(Map.of("artifacts", Map.of("g:a", artifact("1"))));
    data.put("dependencies", Map.of("g:a", List.of("g:missing")));
    assertTrue(invalid(() -> new V4Artifacts(data)).getMessage().contains("g:missing"));
    data.put("dependencies", Map.of("g:parent", List.of("g:a")));
    assertTrue(invalid(() -> new V4Artifacts(data)).getMessage().contains("g:parent"));
  }

  @Test
  public void shouldRecoverSkippedClassifiersOnlyWithKnownVersion() {
    V4Artifacts result =
        new V4Artifacts(
            Map.of(
                "artifacts", Map.of("g:a", artifact("1")), "skipped", List.of("g:a:jar:sources")));
    assertEquals("g:a:1:sources", result.byIdentity.get("g:a:jar:sources").externalForm());
    assertEquals(null, result.byIdentity.get("g:a:jar:sources").sha256);
    invalid(() -> new V4Artifacts(Map.of("skipped", List.of("g:missing"))));
  }

  @Test
  public void shouldDeriveLocalRowsFromM2LocalAndRepositoryMembership() {
    V4Artifacts result =
        new V4Artifacts(
            Map.of(
                "artifacts",
                Map.of("g:a", artifact("1"), "g:b", artifact("1"), "g:c", artifact("1")),
                "m2local",
                true,
                "repositories",
                Map.of("https://repo/", List.of("g:b:jar")),
                "skipped",
                List.of("g:c")));
    assertEquals(Set.of("g:a"), result.local);
    assertEquals(Set.of("g:c"), result.skipped);
  }

  @Test
  public void shouldNormaliseImmediateDependencyAliasesAndOrder() {
    V4Artifacts result =
        new V4Artifacts(
            Map.of(
                "artifacts",
                Map.of("g:a", artifact("1"), "g:b", artifact("2")),
                "dependencies",
                Map.of("g:a:jar", List.of("g:b:jar", "g:b"))));
    assertEquals(Map.of("g:a", List.of("g:b")), result.dependencies);
  }

  private static IllegalArgumentException invalid(Runnable action) {
    try {
      action.run();
    } catch (IllegalArgumentException expected) {
      return expected;
    }
    throw new AssertionError("Expected invalid graph to be rejected");
  }

  private static Map<String, Object> artifact(String version) {
    return Map.of("version", version, "shasums", Map.of("jar", "sha"));
  }
}
