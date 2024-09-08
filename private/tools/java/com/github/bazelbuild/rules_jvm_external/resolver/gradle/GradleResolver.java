package com.github.bazelbuild.rules_jvm_external.resolver.gradle;

import static java.nio.charset.StandardCharsets.UTF_8;

import com.github.bazelbuild.rules_jvm_external.Coordinates;
import com.github.bazelbuild.rules_jvm_external.resolver.Artifact;
import com.github.bazelbuild.rules_jvm_external.resolver.Conflict;
import com.github.bazelbuild.rules_jvm_external.resolver.ResolutionRequest;
import com.github.bazelbuild.rules_jvm_external.resolver.ResolutionResult;
import com.github.bazelbuild.rules_jvm_external.resolver.Resolver;
import com.github.bazelbuild.rules_jvm_external.resolver.events.EventListener;
import com.github.bazelbuild.rules_jvm_external.resolver.events.LogEvent;
import com.github.bazelbuild.rules_jvm_external.resolver.events.PhaseEvent;
import com.github.bazelbuild.rules_jvm_external.resolver.gradle.model.OutgoingArtifactsModel;
import com.github.bazelbuild.rules_jvm_external.resolver.gradle.plugin.CustomModelInjectionPlugin;
import com.github.bazelbuild.rules_jvm_external.resolver.netrc.Netrc;
import com.google.common.base.Strings;
import com.google.common.graph.GraphBuilder;
import com.google.common.graph.ImmutableGraph;
import com.google.common.graph.MutableGraph;
import com.google.devtools.build.runfiles.AutoBazelRepository;
import com.google.devtools.build.runfiles.Runfiles;
import java.io.BufferedReader;
import java.io.ByteArrayInputStream;
import java.io.File;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.UncheckedIOException;
import java.net.URI;
import java.net.URISyntaxException;
import java.nio.charset.Charset;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.security.CodeSource;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.stream.Collectors;

import org.gradle.tooling.GradleConnector;
import org.gradle.tooling.ProjectConnection;
import org.gradle.tooling.internal.consumer.DefaultGradleConnector;

@AutoBazelRepository
public class GradleResolver implements Resolver {

  private final Netrc netrc;
  private final EventListener listener;

  public GradleResolver(Netrc netrc, EventListener listener) {
    this.netrc = Objects.requireNonNull(netrc);
    this.listener = Objects.requireNonNull(listener);
  }

  @Override
  public String getName() {
    return "gradle";
  }

  @Override
  public ResolutionResult resolve(ResolutionRequest request) {
    try {
      return resolveAndMaybeThrow(request);
    } catch (IOException e) {
      throw new UncheckedIOException(e);
    } catch (URISyntaxException e) {
      throw new RuntimeException(e);
    }
  }

  private ResolutionResult resolveAndMaybeThrow(ResolutionRequest request)
      throws IOException, URISyntaxException {
    listener.onEvent(new PhaseEvent("Initialising gradle connector"));
    GradleConnector connector = GradleConnector.newConnector();
    connector.useGradleUserHomeDir(request.getUserHome().toFile());
    ((DefaultGradleConnector) connector).embedded(true);

    Runfiles.Preloaded runfiles = Runfiles.preload();
    String gradleDir =
        runfiles
            .withSourceRepository(AutoBazelRepository_GradleResolver.NAME)
            .rlocation("gradle/gradle-bin/README");
    Path gradlePath = Paths.get(gradleDir).getParent();
    if (!Files.exists(gradlePath)) {
      throw new RuntimeException("Unable to find gradle root at: " + gradlePath);
    }
    connector.useInstallation(gradlePath.toFile());

    Path projectRoot = createTemporaryProject(request);
    connector.forProjectDirectory(projectRoot.toFile());

    listener.onEvent(new PhaseEvent("Gathering dependencies"));
    ProjectConnection connection = connector.connect();

    List<String> args = new ArrayList<>();
    args.addAll(List.of("--init-script", copyInitScript().getAbsolutePath()));
    args.add("--warning-mode=none"); // Don't announce to the world all the problems we find
    args.add("-Dslf4j.internal.verbosity=ERROR");
    args.add("-Dorg.gradle.daemon.idletimeout=1");
    if (System.getenv("RJE_DEBUG") != null) {
      args.addAll(List.of("-Dorg.gradle.debug=true", "-Dorg.gradle.suspend=true"));
    }

    OutgoingArtifactsModel model =
        connection
            .model(OutgoingArtifactsModel.class)
            .withArguments(args)
            .addProgressListener(new GradleEventListener(listener))
            .setStandardError(System.err)
            .setStandardOutput(System.out)
            .get();

    listener.onEvent(new PhaseEvent("Building model"));
    return convert(model);
  }

  private ResolutionResult convert(OutgoingArtifactsModel model) {
    MutableGraph<Coordinates> graph = GraphBuilder.directed().allowsSelfLoops(true).build();
    for (Map.Entry<String, Set<String>> entry : model.getArtifacts().entrySet()) {
      if ("project :".equals(entry.getKey())) {
        continue;
      }
      Coordinates to = new Coordinates(entry.getKey());
      graph.addNode(to);
      for (String dep : entry.getValue()) {
        Coordinates from = new Coordinates(dep);
        graph.addNode(from);
        graph.putEdge(to, from);
      }
    }

    Set<Conflict> conflicts = model.getConflicts().entrySet().stream()
            .map(e -> new Conflict(new Coordinates(e.getValue()), new Coordinates(e.getKey())))
            .collect(Collectors.toSet());

    return new ResolutionResult(ImmutableGraph.copyOf(graph), conflicts);
  }

  private Path createTemporaryProject(ResolutionRequest request) throws IOException {
    StringBuilder contents = new StringBuilder();
    contents.append("repositories {\n");
    for (int i = 0; i < request.getRepositories().size(); i++) {
      URI uri = request.getRepositories().get(0);
      contents.append("  maven").append(" {\n    url = uri(\"").append(uri).append("\")\n");
      if ("http".equals(uri.getScheme())) {
        contents.append("    allowInsecureProtocol = true\n");
      }
      Netrc.Credential credential =
          netrc.credentials().entrySet().stream()
              .filter(e -> e.getKey().equals(uri.getHost()))
              .findFirst()
              .map(Map.Entry::getValue)
              .orElse(netrc.defaultCredential());
      if (credential != null) {
        contents.append("    credentials {\n");
        contents.append("        username \"").append(credential.login()).append("\"\n");
        contents.append("        password \"").append(credential.password()).append("\"\n");
        contents.append("    }\n");
      }

      contents.append("  }\n");
    }
    contents.append("}\n\n");

    contents.append("dependencies {\n");
    for (Artifact bom : request.getBoms()) {
      // We need to remove the `pom` classifier if gradle is going to be happy
      Coordinates defaultCoords = bom.getCoordinates().setClassifier("jar").setExtension(null);
      contents
          .append("  implementation platform(")
          .append(toGradleDependencyNotation(new Artifact(defaultCoords, bom.getExclusions())))
          .append(")\n");
    }

    for (Artifact dep : request.getDependencies()) {
      contents.append("  implementation(").append(toGradleDependencyNotation(dep)).append(")\n");
    }
    contents.append("}\n\n");

    // Add any global exclusions
    if (!request.getGlobalExclusions().isEmpty()) {
      contents.append("configurations.all {\n");
      request.getGlobalExclusions().forEach(e -> {
        contents.append("  exclude group: '").append(e.getGroupId()).append("', module: '").append(e.getArtifactId()).append("'\n");
      });
      contents.append("}\n\n");
    }

    if (System.getenv("RJE_VERBOSE") != null) {
      listener.onEvent(new LogEvent("gradle", contents.toString(), null));
    }

    Path root = Files.createTempDirectory("rje_resolver");
    Files.write(root.resolve("build.gradle"), contents.toString().getBytes(UTF_8));

    Files.write(
        root.resolve("gradle.properties"),
        "org.gradle.parallel=true\norg.gradle.caching=true\norg.gradle.debug=true\norg.gradle.debug.suspend=true\n"
            .getBytes(UTF_8));

    return root;
  }

  private String toGradleDependencyNotation(Artifact artifact) {
    Coordinates coords = artifact.getCoordinates();
    StringBuilder toReturn =
        new StringBuilder()
            .append("'")
            .append(coords.getGroupId())
            .append(":")
            .append(coords.getArtifactId());
    if (!Strings.isNullOrEmpty(coords.getVersion())) {
      toReturn.append(":").append(coords.getVersion());
    }
    if (!Strings.isNullOrEmpty(coords.getClassifier())) {
      toReturn.append(":").append(coords.getClassifier());
    }
    if (!Strings.isNullOrEmpty(coords.getExtension()) && !"jar".equals(coords.getExtension())) {
      toReturn.append("@").append(coords.getExtension());
    }
    toReturn.append("'");

    if (!artifact.getExclusions().isEmpty()) {
      toReturn.append(" {\n");
      for (Coordinates exclusion : artifact.getExclusions()) {
        toReturn
            .append("  exclude group: '")
            .append(exclusion.getGroupId())
            .append("', module: '")
            .append(exclusion.getArtifactId())
            .append("'\n");
      }
      toReturn.append("}\n");
    }

    return toReturn.toString();
  }

  private File copyInitScript() throws IOException, URISyntaxException {
    Path init = Files.createTempFile("init", ".gradle");
    StringBuilder sb = new StringBuilder();
    File pluginJar = lookupJar(CustomModelInjectionPlugin.class);
    File modelJar = lookupJar(OutgoingArtifactsModel.class);
    String name = "/" + getClass().getPackageName().replace('.', '/') + "/init.gradle";

    try (BufferedReader reader =
        new BufferedReader(new InputStreamReader(getClass().getResourceAsStream(name)))) {
      reader
          .lines()
          .forEach(
              line -> {
                String repl =
                    line.replace("%%PLUGIN_JAR%%", pluginJar.getAbsolutePath())
                        .replace("%%MODEL_JAR%%", modelJar.getAbsolutePath());
                // fix paths if we're on Windows
                if (File.separatorChar == '\\') {
                  repl = repl.replace('\\', '/');
                }
                sb.append(repl).append("\n");
              });
    }
    Files.copy(
        new ByteArrayInputStream(sb.toString().getBytes(Charset.defaultCharset())),
        init,
        StandardCopyOption.REPLACE_EXISTING);
    return init.toFile();
  }

  private File lookupJar(Class<?> beaconClass) throws URISyntaxException {
    CodeSource codeSource = beaconClass.getProtectionDomain().getCodeSource();
    return new File(codeSource.getLocation().toURI());
  }
}
