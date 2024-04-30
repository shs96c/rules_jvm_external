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
import org.gradle.internal.operations.BuildOperationDescriptor;
import org.gradle.internal.operations.BuildOperationIdFactory;
import org.gradle.internal.operations.BuildOperationProgressEventEmitter;
import org.gradle.internal.operations.OperationIdentifier;
import org.gradle.internal.service.ServiceRegistry;
import org.gradle.tooling.provider.model.ToolingModelBuilder;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.File;
import java.lang.reflect.Field;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.Set;

public class OutgoingArtifactsModelBuilder implements ToolingModelBuilder {
    private static final Logger log = LoggerFactory.getLogger(OutgoingArtifactsModelBuilder.class);
    private static final String MODEL_NAME = OutgoingArtifactsModel.class.getName();
    private final ArtifactDependencyResolver artifactResolver;
    private final BuildOperationProgressEventEmitter emitter;
    private final BuildOperationIdFactory buildOperationIdFactory;

    public OutgoingArtifactsModelBuilder(ArtifactDependencyResolver resolver, BuildOperationIdFactory buildOperationIdFactory, BuildOperationProgressEventEmitter emitter) {
        this.artifactResolver = resolver;
        this.buildOperationIdFactory = buildOperationIdFactory;
        this.emitter = emitter;
    }

    @Override
    public boolean canBuild(String modelName) {
        return modelName.equals(MODEL_NAME);
    }

    @Override
    public Object buildAll(String modelName, Project project) {
        OperationIdentifier opId = new OperationIdentifier(buildOperationIdFactory.nextId());
        BuildOperationDescriptor event = BuildOperationDescriptor.displayName("woo")
                .progressDisplayName("I like cake")
                .build(opId, null);
        emitter.emitNowForCurrent(event);
        emitter.emitNowIfCurrent(event);
        emitter.emit(opId, 1, event);

        try {
            for (Field f : emitter.getClass().getDeclaredFields()) {
                f.setAccessible(true);
                System.err.printf("Emitter: %s - %s -> %s%n", f.getName(), f.getType(), f.get(emitter));
            }


            Field listener = emitter.getClass().getDeclaredField("listener");
            listener.setAccessible(true);
            Object value = listener.get(emitter);
            System.err.println("Listener: " + value + " -> " + value.getClass());
            for (Field f : value.getClass().getDeclaredFields()) {
                f.setAccessible(true);
                System.err.printf("Listener: %s - %s -> %s%n", f.getName(), f.getType(), f.get(value));
            }
        } catch (ReflectiveOperationException e) {
            e.printStackTrace();
        }

        Set<File> artifacts = new LinkedHashSet<>();

        ServiceRegistry services = ((DefaultProject) project).getServices();
        GlobalDependencyResolutionRules resolutionRules =
                services.get(GlobalDependencyResolutionRules.class);
        artifacts.add(new File(resolutionRules.toString()));

        BuildOperationProgressEventEmitter e2 = services.get(BuildOperationProgressEventEmitter.class);
        System.err.println("E2 is " + e2 + " and emitter is " + emitter + " class name: " + emitter.getClass().getName());
        e2.emitNowIfCurrent(event);
        e2.emitNowForCurrent(event);
        e2.emitIfCurrent(1024, event);

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
