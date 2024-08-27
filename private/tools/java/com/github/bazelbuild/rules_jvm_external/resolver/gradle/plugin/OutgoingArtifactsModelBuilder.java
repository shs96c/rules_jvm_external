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
import org.gradle.api.Project;
import org.gradle.api.artifacts.Configuration;
import org.gradle.api.artifacts.ConfigurationContainer;
import org.gradle.api.artifacts.result.DependencyResult;
import org.gradle.api.artifacts.result.ResolvedComponentResult;
import org.gradle.api.artifacts.result.ResolvedDependencyResult;
import org.gradle.api.attributes.Attribute;
import org.gradle.api.attributes.AttributeContainer;
import org.gradle.api.attributes.Category;
import org.gradle.tooling.provider.model.ToolingModelBuilder;

import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import java.util.TreeSet;

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
    ResolvedComponentResult result =
        defaultConfig.getIncoming().getResolutionResult().getRootComponent().get();

    Map<String, Set<String>> artifacts = new TreeMap<>();
    reportComponent(result, artifacts);

    return new DefaultOutgoingArtifactsModel(artifacts);
  }

  private void reportComponent(
      ResolvedComponentResult component, Map<String, Set<String>> artifacts) {
    String componentName = component.getId().getDisplayName();
    Set<String> knownDeps = artifacts.computeIfAbsent(componentName, ignored -> new TreeSet<>());

    for (DependencyResult dependency : component.getDependencies()) {
      if (dependency instanceof ResolvedDependencyResult) {
        ResolvedDependencyResult resolvedDependency = (ResolvedDependencyResult) dependency;

        if (isLibraryComponent(resolvedDependency)) {
          knownDeps.add(dependency.getRequested().getDisplayName());
        }
        reportComponent(resolvedDependency.getSelected(), artifacts);
      } else {
        System.err.println("The was: " + dependency.getClass());
      }
    }
    artifacts.put(componentName, knownDeps);
  }

  private boolean isLibraryComponent(ResolvedDependencyResult result) {
    AttributeContainer attributes = result.getRequested().getAttributes();

    Attribute<?> category = attributes.keySet().stream()
            .filter(a -> CATEGORY_ATTRIBUTE.getName().equals(a.getName()))
            .findFirst()
            .orElse(null);

    if (category == null) {
      return true;
    }

    Object attribute = attributes.getAttribute(category);
    return Category.LIBRARY.equals(attribute);
  }
}
