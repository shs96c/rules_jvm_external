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
    Map<ComponentIdentifier, File> knownFiles = collectDownloadedFiles(resolvedArtifactResults);

    ResolvedComponentResult result = resolvableDeps.getResolutionResult().getRootComponent().get();
    Graph<ResolutionData> graph = buildDependencyGraph(result, knownFiles);

    Map<String, Set<String>> artifacts = reconstructDependencyGraph(project, graph, knownFiles);

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

  private Graph<ResolutionData> buildDependencyGraph(
      ResolvedComponentResult result, Map<ComponentIdentifier, File> knownFiles) {
    MutableGraph<ResolutionData> toReturn = GraphBuilder.directed().build();
    amendDependencyGraph(toReturn, result, knownFiles);
    return ImmutableGraph.copyOf(toReturn);
  }

  private void amendDependencyGraph(
      MutableGraph<ResolutionData> toReturn,
      ResolvedComponentResult result,
      Map<ComponentIdentifier, File> knownFiles) {
    ComponentIdentifier id = result.getId();

    ResolutionData parent = new ResolutionData(result, knownFiles.get(id));

    if (id instanceof ModuleComponentIdentifier) {
      toReturn.addNode(parent);
    }

    for (ResolvedVariantResult variant : result.getVariants()) {
      List<DependencyResult> depsForVariant = result.getDependenciesForVariant(variant);
      for (DependencyResult dep : depsForVariant) {
        if (dep instanceof ResolvedDependencyResult) {
          ResolvedDependencyResult resolved = (ResolvedDependencyResult) dep;
          ResolvedComponentResult selected = resolved.getSelected();

          ResolutionData child =
              new ResolutionData(resolved.getSelected(), knownFiles.get(selected.getId()));

          if (toReturn.nodes().contains(child)) {
            continue;
          }

          if (selected.getId() instanceof ModuleComponentIdentifier) {
            toReturn.addNode(child);
            toReturn.putEdge(parent, child);
          }

          amendDependencyGraph(toReturn, selected, knownFiles);
        } else {
          System.err.println(String.format("Cannot resolve %s (class %s)", dep, dep.getClass()));
        }
      }
    }
  }

  private Map<String, Set<String>> reconstructDependencyGraph(
      Project project, Graph<ResolutionData> graph, Map<ComponentIdentifier, File> knownFiles) {
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
    Set<ResolutionData> roots =
        graph.nodes().stream()
            .filter(rd -> rd.getResult().getId() instanceof ModuleComponentIdentifier)
            .filter(
                rd ->
                    identifiers.contains(
                        ((ModuleComponentIdentifier) rd.getResult().getId()).getModuleIdentifier()))
            .collect(Collectors.toSet());

    Map<String, Set<String>> toReturn = new HashMap<>();
    for (ResolutionData root : roots) {
      reconstructDependencyGraph(root, graph, knownFiles, toReturn);
    }

    return Map.copyOf(toReturn);
  }

  private void reconstructDependencyGraph(
      ResolutionData toVisit,
      Graph<ResolutionData> graph,
      Map<ComponentIdentifier, File> knownFiles,
      Map<String, Set<String>> visited) {
    ComponentIdentifier tempId = toVisit.getResult().getId();

    if (!(tempId instanceof ModuleComponentIdentifier)) {
      return;
    }

    ModuleComponentIdentifier id = (ModuleComponentIdentifier) tempId;
    String key = createKey(id);

    if (visited.containsKey(key)) {
      return;
    }

    // To prevent recursion if there's a loop in the graph

    Set<ResolutionData> successors = graph.successors(toVisit);
    Set<ResolutionData> recurseInto =
        successors.stream()
            .filter(rd -> rd.getResult().getId() instanceof ModuleComponentIdentifier)
            .collect(Collectors.toSet());
    visited.put(
        key,
        recurseInto.stream()
            .map(rd -> createKey((ModuleComponentIdentifier) rd.getResult().getId()))
            .collect(Collectors.toSet()));
    for (ResolutionData dep : recurseInto) {
      reconstructDependencyGraph(dep, graph, knownFiles, visited);
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
