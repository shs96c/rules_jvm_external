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
package com.github.bazelbuild.rules_jvm_external.resolver.gradle2.plugin;

import com.github.bazelbuild.rules_jvm_external.resolver.gradle2.model.DefaultOutgoingArtifactsModel;
import com.github.bazelbuild.rules_jvm_external.resolver.gradle2.model.OutgoingArtifactsModel;
import org.gradle.api.Project;
import org.gradle.api.artifacts.Configuration;
import org.gradle.api.artifacts.ConfigurationContainer;
import org.gradle.api.artifacts.result.DependencyResult;
import org.gradle.api.artifacts.result.ResolvedComponentResult;
import org.gradle.api.artifacts.result.ResolvedDependencyResult;
import org.gradle.tooling.provider.model.ToolingModelBuilder;

import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.TreeSet;

public class OutgoingArtifactsModelBuilder implements ToolingModelBuilder {
    private static final String MODEL_NAME = OutgoingArtifactsModel.class.getName();

    public OutgoingArtifactsModelBuilder() {
    }

    @Override
    public boolean canBuild(String modelName) {
        return modelName.equals(MODEL_NAME);
    }

    @Override
    public Object buildAll(String modelName, Project project) {
        ConfigurationContainer configs = project.getConfigurations();
        for (Configuration config : configs) {
            System.err.println("config: " + config.getName());
        }
        Configuration defaultConfig = configs.getByName("compileClasspath");
        ResolvedComponentResult result = defaultConfig.getIncoming().getResolutionResult().getRootComponent().get();

        Set<String> artifacts = new TreeSet<>();
        reportComponent(result, artifacts);

        return new DefaultOutgoingArtifactsModel(artifacts);
    }

    private void reportComponent(ResolvedComponentResult component, Set<String> artifacts) {
        for (DependencyResult dependency : component.getDependencies()) {
            artifacts.add(dependency.getRequested().getDisplayName());

            if (dependency instanceof ResolvedDependencyResult) {
                ResolvedDependencyResult resolvedDependency = (ResolvedDependencyResult) dependency;
                reportComponent(resolvedDependency.getSelected(), artifacts);
            }
        }
    }
}
