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
import org.gradle.api.artifacts.ResolvedArtifact;
import org.gradle.api.internal.artifacts.ArtifactDependencyResolver;
import org.gradle.api.internal.artifacts.GlobalDependencyResolutionRules;
import org.gradle.api.internal.project.DefaultProject;
import org.gradle.internal.service.ServiceRegistry;
import org.gradle.tooling.ProgressListener;
import org.gradle.tooling.provider.model.ToolingModelBuilder;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.File;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.Set;

public class OutgoingArtifactsModelBuilder implements ToolingModelBuilder {
    private static final Logger log = LoggerFactory.getLogger(OutgoingArtifactsModelBuilder.class);
    private static final String MODEL_NAME = OutgoingArtifactsModel.class.getName();
    private final ArtifactDependencyResolver artifactResolver;

    public OutgoingArtifactsModelBuilder(ArtifactDependencyResolver resolver) {
        this.artifactResolver = resolver;
    }

    @Override
    public boolean canBuild(String modelName) {
        return modelName.equals(MODEL_NAME);
    }

    @Override
    public Object buildAll(String modelName, Project project) {
        Set<File> artifacts = new LinkedHashSet<>();

        ServiceRegistry services = ((DefaultProject) project).getServices();
        GlobalDependencyResolutionRules resolutionRules =
                services.get(GlobalDependencyResolutionRules.class);
        artifacts.add(new File(resolutionRules.toString()));

        ConfigurationContainer configs = project.getConfigurations();
        Configuration defaultConfig = configs.getByName("default");
        Set<ResolvedArtifact> resolvedArtifacts = defaultConfig.getResolvedConfiguration().getResolvedArtifacts();
        resolvedArtifacts.forEach(a -> artifacts.add(new File(a.getId().toString())));

        defaultConfig.getDependencies().stream()
                        .forEach(d -> artifacts.add(new File(d.getName())));


        project.allprojects(p -> {
            for (Configuration configuration : p.getConfigurations()) {
                if (configuration.isCanBeConsumed()) {
                    artifacts.addAll(configuration.getArtifacts().getFiles().getFiles());
                }
            }
        });
        return new DefaultOutgoingArtifactsModel(new ArrayList<>(artifacts));
    }
}
