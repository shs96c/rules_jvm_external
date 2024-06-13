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
package com.github.bazelbuild.rules_jvm_external.resolver.gradle2.tapi;

import com.github.bazelbuild.rules_jvm_external.resolver.gradle2.model.OutgoingArtifactsModel;
import com.github.bazelbuild.rules_jvm_external.resolver.gradle2.plugin.CustomModelInjectionPlugin;
import com.google.common.base.Joiner;
import com.google.common.graph.Graph;
import com.google.common.graph.GraphBuilder;
import com.google.common.graph.ImmutableGraph;
import com.google.common.graph.MutableGraph;
import com.google.devtools.build.runfiles.Runfiles;
import org.gradle.tooling.GradleConnector;
import org.gradle.tooling.ModelBuilder;
import org.gradle.tooling.ProgressEvent;
import org.gradle.tooling.ProgressListener;
import org.gradle.tooling.ProjectConnection;
import org.gradle.tooling.internal.consumer.DefaultGradleConnector;

import java.io.BufferedReader;
import java.io.ByteArrayInputStream;
import java.io.File;
import java.io.IOException;
import java.io.InputStreamReader;
import java.net.URISyntaxException;
import java.nio.charset.Charset;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.security.CodeSource;
import java.util.Map;
import java.util.Set;

public class App {
    public static void main(String... args) throws Exception {
        System.err.println("Creating a new gradle connector");
        GradleConnector connector = GradleConnector.newConnector();
        File projectPath = findProjectPath(System.getenv("BUILD_WORKING_DIRECTORY"));
        connector.forProjectDirectory(projectPath);
        ((DefaultGradleConnector) connector).embedded(true);

        Runfiles.Preloaded runfiles = Runfiles.preload();
        String gradleDir = runfiles.unmapped().rlocation(System.getenv("GRADLE_ROOT"));
        Path gradlePath = Paths.get(gradleDir).getParent();
        if (!Files.exists(gradlePath)) {
            throw new RuntimeException("Unable to find gradle root at: " + gradlePath);
        }
        connector.useInstallation(gradlePath.toFile());

        ProjectConnection connection = null;
        try {
            System.err.println("About to connect to project");
            connection = connector.connect();
            ModelBuilder<OutgoingArtifactsModel> modelBuilder = connection.model(OutgoingArtifactsModel.class);
            modelBuilder.setStandardError(System.err);
            modelBuilder.setStandardOutput(System.out);
            modelBuilder.addProgressListener((ProgressListener) progressEvent -> System.err.printf("event: %s -> %s%n", progressEvent.getClass(), progressEvent.getDescription()));
            modelBuilder.withArguments("--init-script", copyInitScript().getAbsolutePath());
            OutgoingArtifactsModel model = modelBuilder.get();

            Map<String, Set<String>> rawGraph = model.getArtifacts();

            Joiner.MapJoiner mapJoiner = Joiner.on("\n").withKeyValueSeparator("=");
            System.err.println(mapJoiner.join(rawGraph));

            MutableGraph<String> graph = GraphBuilder.directed()
                    .allowsSelfLoops(true)
                    .build();

            for (Map.Entry<String, Set<String>> entry : rawGraph.entrySet()) {
                graph.addNode(entry.getKey());
                for (String value : entry.getValue()) {
                    graph.addNode(value);
                    graph.putEdge(entry.getKey(), value);
                }
            }

            Graph<String> finalGraph = ImmutableGraph.copyOf(graph);
            System.err.println(finalGraph);
        } finally {
            if (connection != null) {
                connection.close();
            }
            connector.disconnect();
        }
        System.exit(0);
    }

    private static File copyInitScript() throws IOException, URISyntaxException {
        Path init = Files.createTempFile("init", ".gradle");
        StringBuilder sb = new StringBuilder();
        File pluginJar = lookupJar(CustomModelInjectionPlugin.class);
        File modelJar = lookupJar(OutgoingArtifactsModel.class);
        String name = "/" + App.class.getPackageName().replace('.', '/') + "/init.gradle";

        try (BufferedReader reader = new BufferedReader(new InputStreamReader(App.class.getResourceAsStream(name)))) {
            reader.lines()
                    .forEach(line -> {
                        String repl = line.replace("%%PLUGIN_JAR%%", pluginJar.getAbsolutePath())
                                .replace("%%MODEL_JAR%%", modelJar.getAbsolutePath());
                        // fix paths if we're on Windows
                        if (File.separatorChar=='\\') {
                            repl = repl.replace('\\', '/');
                        }
                        sb.append(repl).append("\n");
                    });
        }
        Files.copy(new ByteArrayInputStream(sb.toString().getBytes(Charset.defaultCharset())),
                init,
                StandardCopyOption.REPLACE_EXISTING);
        return init.toFile();
    }

    private static File lookupJar(Class<?> beaconClass) throws URISyntaxException {
        CodeSource codeSource = beaconClass.getProtectionDomain().getCodeSource();
        return new File(codeSource.getLocation().toURI());
    }

    private static File findProjectPath(String... args) {
        if (args.length == 0) {
            return new File(".").getAbsoluteFile();
        }
        return new File(args[0]);
    }
}
