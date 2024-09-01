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

import com.github.bazelbuild.rules_jvm_external.resolver.gradle.model.DefaultOutgoingArtifactsModel;
import com.github.bazelbuild.rules_jvm_external.resolver.gradle.model.OutgoingArtifactsModel;
import com.google.common.graph.Graph;
import com.google.common.graph.GraphBuilder;
import com.google.common.graph.ImmutableGraph;
import com.google.common.graph.MutableGraph;
import org.gradle.api.Project;
import org.gradle.api.artifacts.Configuration;
import org.gradle.api.artifacts.ConfigurationContainer;
import org.gradle.api.artifacts.ResolvableDependencies;
import org.gradle.api.artifacts.component.ComponentIdentifier;
import org.gradle.api.artifacts.component.ModuleComponentIdentifier;
import org.gradle.api.artifacts.result.DependencyResult;
import org.gradle.api.artifacts.result.ResolvedArtifactResult;
import org.gradle.api.artifacts.result.ResolvedComponentResult;
import org.gradle.api.artifacts.result.ResolvedDependencyResult;
import org.gradle.api.artifacts.result.ResolvedVariantResult;
import org.gradle.api.attributes.Attribute;
import org.gradle.api.attributes.AttributeContainer;
import org.gradle.api.attributes.Category;
import org.gradle.tooling.provider.model.ToolingModelBuilder;

import java.io.File;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import java.util.TreeSet;
import java.util.stream.Collectors;

import static org.gradle.api.attributes.Category.CATEGORY_ATTRIBUTE;

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

    Set<ResolvedArtifactResult> resolvedArtifactResults = resolvableDeps.getArtifacts().getResolvedArtifacts().get();
    Map<ComponentIdentifier, File> knownFiles = collectDownloadedFiles(resolvedArtifactResults);

    ResolvedComponentResult result = resolvableDeps.getResolutionResult().getRootComponent().get();
    Graph<ResolutionData> graph = buildDependencyGraph(result, knownFiles);
    System.err.println("Graph is: " + graph);
    System.err.println(graph.nodes().stream()
            .map(d -> String.format("%s -> %s", d.getResult().getId(), (d.getFile() == null ? "null" : d.getFile().getName())))
            .collect(Collectors.joining("\n")));

    Map<String, Set<String>> artifacts = new TreeMap<>();

    // Walk the graph. If a node is not a library

    return new DefaultOutgoingArtifactsModel(artifacts);
  }

  private Map<ComponentIdentifier, File> collectDownloadedFiles(Set<ResolvedArtifactResult> result) {
    Map<ComponentIdentifier, File> knownFiles = new HashMap<>();

    for (ResolvedArtifactResult artifactResult : result) {
      knownFiles.put(artifactResult.getId().getComponentIdentifier(), artifactResult.getFile());
    }

    return Map.copyOf(knownFiles);
  }

  private Graph<ResolutionData> buildDependencyGraph(ResolvedComponentResult result, Map<ComponentIdentifier, File> knownFiles) {
    MutableGraph<ResolutionData> toReturn = GraphBuilder.directed().build();
    amendDependencyGraph(toReturn, result, knownFiles);
    return ImmutableGraph.copyOf(toReturn);
  }

  private void amendDependencyGraph(MutableGraph<ResolutionData> toReturn, ResolvedComponentResult result, Map<ComponentIdentifier, File> knownFiles) {
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

          ResolutionData child = new ResolutionData(resolved.getSelected(), knownFiles.get(selected.getId()));

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
}
