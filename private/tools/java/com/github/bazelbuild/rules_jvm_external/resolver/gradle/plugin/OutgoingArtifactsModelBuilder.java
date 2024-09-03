/*
 * Copyright 2003-2012 the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package com.github.bazelbuild.rules_jvm_external.resolver.gradle.plugin;

import static com.github.bazelbuild.rules_jvm_external.resolver.gradle.plugin.Attributes.isPlatform;

import com.github.bazelbuild.rules_jvm_external.resolver.gradle.model.DefaultOutgoingArtifactsModel;
import com.github.bazelbuild.rules_jvm_external.resolver.gradle.model.OutgoingArtifactsModel;
import com.google.common.graph.Graph;
import com.google.common.graph.GraphBuilder;
import com.google.common.graph.ImmutableGraph;
import com.google.common.graph.MutableGraph;
import java.io.File;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;
import org.gradle.api.Project;
import org.gradle.api.artifacts.Configuration;
import org.gradle.api.artifacts.ConfigurationContainer;
import org.gradle.api.artifacts.ExternalModuleDependency;
import org.gradle.api.artifacts.ModuleIdentifier;
import org.gradle.api.artifacts.ModuleVersionSelector;
import org.gradle.api.artifacts.ResolvableDependencies;
import org.gradle.api.artifacts.component.ComponentIdentifier;
import org.gradle.api.artifacts.component.ModuleComponentIdentifier;
import org.gradle.api.artifacts.result.DependencyResult;
import org.gradle.api.artifacts.result.ResolvedArtifactResult;
import org.gradle.api.artifacts.result.ResolvedComponentResult;
import org.gradle.api.artifacts.result.ResolvedDependencyResult;
import org.gradle.api.artifacts.result.ResolvedVariantResult;
import org.gradle.tooling.provider.model.ToolingModelBuilder;

public class OutgoingArtifactsModelBuilder implements ToolingModelBuilder {
  private static final String MODEL_NAME = OutgoingArtifactsModel.class.getName();

  public OutgoingArtifactsModelBuilder() {}

  @Override
  public boolean canBuild(String modelName) {
    return modelName.equals(MODEL_NAME);
  }

  @Override
  public Object buildAll(String modelName, Project project) {
    ConfigurationContainer configs = project.getConfigurations();
    Configuration defaultConfig = configs.getByName("default");
    ResolvableDependencies resolvableDeps = defaultConfig.getIncoming();

    Set<ResolvedArtifactResult> resolvedArtifactResults =
        resolvableDeps.getArtifacts().getResolvedArtifacts().get();

    // Begin by constructing the possible graph of what we want. Gradle will
    // resolve things at the "module" level (`groupId:artifactId`) and will
    // "loose" results that only differ by classifier. Because of this, the
    // graph we have is possibly incomplete, but it's a good place to start
    // from.
    ResolvedComponentResult result = resolvableDeps.getResolutionResult().getRootComponent().get();
    Graph<ResolvedComponentResult> graph = buildDependencyGraph(result);

    // We now rely on the downloaded files to be named following the default
    // maven format so that we can calculate the coordinates that they would
    // represent.
    Map<ComponentIdentifier, File> knownFiles = collectDownloadedFiles(resolvedArtifactResults);

    // Given the (possibly incomplete) graph of dependencies, and the list of
    // possible coordinates, we can now make a decent attempt at
    // reconstructing something that includes all the dependencies that have
    // been downloaded.

    Map<String, Set<String>> artifacts = reconstructDependencyGraph(project, graph);

    return new DefaultOutgoingArtifactsModel(artifacts);
  }

  private Map<ComponentIdentifier, File> collectDownloadedFiles(
      Set<ResolvedArtifactResult> result) {
    Map<ComponentIdentifier, File> knownFiles = new HashMap<>();

    for (ResolvedArtifactResult artifactResult : result) {
      knownFiles.put(artifactResult.getId().getComponentIdentifier(), artifactResult.getFile());
    }

    return Map.copyOf(knownFiles);
  }

  private Graph<ResolvedComponentResult> buildDependencyGraph(ResolvedComponentResult result) {
    MutableGraph<ResolvedComponentResult> toReturn = GraphBuilder.directed().build();
    amendDependencyGraph(toReturn, result);
    return ImmutableGraph.copyOf(toReturn);
  }

  private void amendDependencyGraph(
      MutableGraph<ResolvedComponentResult> toReturn, ResolvedComponentResult result) {
    ComponentIdentifier id = result.getId();

    if (id instanceof ModuleComponentIdentifier) {
      toReturn.addNode(result);
    }

    for (ResolvedVariantResult variant : result.getVariants()) {
      List<DependencyResult> depsForVariant = result.getDependenciesForVariant(variant);
      for (DependencyResult dep : depsForVariant) {
        if (dep instanceof ResolvedDependencyResult) {
          ResolvedDependencyResult resolved = (ResolvedDependencyResult) dep;
          ResolvedComponentResult selected = resolved.getSelected();

          if (toReturn.nodes().contains(selected)) {
            continue;
          }

          if (selected.getId() instanceof ModuleComponentIdentifier) {
            toReturn.addNode(selected);
            toReturn.putEdge(result, selected);
          }

          amendDependencyGraph(toReturn, selected);
        } else {
          System.err.println(String.format("Cannot resolve %s (class %s)", dep, dep.getClass()));
        }
      }
    }
  }

  private Map<String, Set<String>> reconstructDependencyGraph(
      Project project, Graph<ResolvedComponentResult> graph) {
    // Get the list of dependencies that the user actually asked for
    Set<ExternalModuleDependency> requestedDeps = new HashSet<>();
    for (Configuration config : project.getConfigurations()) {
      config.getDependencies().stream()
          .filter(d -> d instanceof ExternalModuleDependency)
          .map(d -> (ExternalModuleDependency) d)
          .filter(d -> !isPlatform(d.getAttributes()))
          .forEach(requestedDeps::add);
    }

    // Now get the module identifiers for the requested deps
    Set<ModuleIdentifier> identifiers =
        requestedDeps.stream().map(ModuleVersionSelector::getModule).collect(Collectors.toSet());

    // And then find the results that match the requested artifacts.
    // These will form the root of our graph
    Set<ResolvedComponentResult> roots =
        graph.nodes().stream()
            .filter(rd -> rd.getId() instanceof ModuleComponentIdentifier)
            .filter(
                rd ->
                    identifiers.contains(
                        ((ModuleComponentIdentifier) rd.getId()).getModuleIdentifier()))
            .collect(Collectors.toSet());

    Map<String, Set<String>> toReturn = new HashMap<>();
    for (ResolvedComponentResult root : roots) {
      reconstructDependencyGraph(root, graph, toReturn);
    }

    return Map.copyOf(toReturn);
  }

  private void reconstructDependencyGraph(
      ResolvedComponentResult toVisit,
      Graph<ResolvedComponentResult> graph,
      Map<String, Set<String>> visited) {
    ComponentIdentifier tempId = toVisit.getId();

    if (!(tempId instanceof ModuleComponentIdentifier)) {
      return;
    }

    ModuleComponentIdentifier id = (ModuleComponentIdentifier) tempId;
    String key = createKey(id);

    if (visited.containsKey(key)) {
      return;
    }

    Set<ResolvedComponentResult> successors = graph.successors(toVisit);
    Set<ResolvedComponentResult> recurseInto =
        successors.stream()
            .filter(rd -> rd.getId() instanceof ModuleComponentIdentifier)
            .collect(Collectors.toSet());
    visited.put(
        key,
        recurseInto.stream()
            .map(rd -> createKey((ModuleComponentIdentifier) rd.getId()))
            .collect(Collectors.toSet()));
    for (ResolvedComponentResult dep : recurseInto) {
      reconstructDependencyGraph(dep, graph, visited);
    }
  }

  private String createKey(ModuleComponentIdentifier id) {
    StringBuilder coords = new StringBuilder();
    coords.append(id.getGroup()).append(":").append(id.getModule());
    if (id.getVersion() != null) {
      coords.append(":").append(id.getVersion());
    }
    return coords.toString();
  }
}
