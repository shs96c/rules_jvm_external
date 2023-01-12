package com.github.bazelbuild.rules_jvm_external.coursier;

import static java.nio.charset.StandardCharsets.UTF_8;

import com.github.bazelbuild.rules_jvm_external.Coordinates;
import com.github.bazelbuild.rules_jvm_external.MavenRepositoryPath;
import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.reflect.TypeToken;
import java.io.IOException;
import java.io.Reader;
import java.io.UncheckedIOException;
import java.io.UnsupportedEncodingException;
import java.net.URLDecoder;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Collection;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.TreeMap;
import java.util.TreeSet;
import java.util.stream.Collectors;

/** Reads the output of the coursier resolve and generate a v2 lock file */
public class LockFileConverter {

  private final Set<String> repositories;
  private final Path unsortedJson;

  public static void main(String[] args) {
    Path unsortedJson = null;
    Path output = null;
    // Insertion order matters
    Set<String> repositories = new LinkedHashSet<>();

    for (int i = 0; i < args.length; i++) {
      switch (args[i]) {
        case "--json":
          i++;
          unsortedJson = Paths.get(args[i]);
          break;

        case "--output":
          i++;
          output = Paths.get(args[i]);
          break;

        case "--repo":
          i++;
          // Make sure the repos end with a slash
          if (args[i].endsWith("/")) {
            repositories.add(args[i]);
          } else {
            repositories.add(args[i] + "/");
          }
          break;

        default:
          throw new IllegalArgumentException("Unknown command line option: " + args[i]);
      }
    }

    if (unsortedJson == null) {
      System.err.println(
          "Path to coursier-generated lock file is required. Add using the `--json` flag");
      System.exit(1);
    }

    Map<String, Object> lockContents =
        new LockFileConverter(repositories, unsortedJson).generateV2LockFile();

    String converted = new GsonBuilder().setPrettyPrinting().create().toJson(lockContents);

    if (output == null) {
      System.out.println(converted);
    } else {
      try {
        Files.write(output, converted.getBytes(UTF_8));
      } catch (IOException e) {
        throw new UncheckedIOException(e);
      }
    }
  }

  public LockFileConverter(Set<String> repositories, Path unsortedJson) {
    this.repositories = Objects.requireNonNull(repositories);
    this.unsortedJson = Objects.requireNonNull(unsortedJson);
  }

  public Map<String, Object> generateV2LockFile() {
    boolean isUsingM2Local =
        repositories.stream().map(String::toLowerCase).anyMatch(repo -> repo.equals("m2local/"));

    Map<String, Object> depTree = readDepTree();

    Map<Coordinates, Coordinates> mappings = deriveCoordinateMappings(depTree);

    Set<String> artifacts = new TreeSet<>();
    Map<String, Set<String>> deps = new TreeMap<>();
    Map<String, Map<String, String>> shasums = new TreeMap<>();
    Map<String, Set<String>> packages = new TreeMap<>();
    // Insertion order matters
    Map<String, Set<String>> repos = new LinkedHashMap<>();
    repositories.forEach(r -> repos.put(r, new TreeSet<>()));

    Set<String> skippedDeps = new TreeSet<>();
    Map<Coordinates, String> fileMappings = new TreeMap<>();

    @SuppressWarnings("unchecked")
    Collection<Map<String, Object>> coursierDeps =
        (Collection<Map<String, Object>>) depTree.get("dependencies");
    for (Map<String, Object> coursierDep : coursierDeps) {
      @SuppressWarnings("unchecked")
      String coord = (String) coursierDep.get("coord");
      Coordinates coords = mappings.get(new Coordinates(coord));
      String key = coords.asKey();
      String altKey = coords.setClassifier("jar").asKey();

      if (isSkipDep(coursierDep)) {
        // Coursier likes to include things that may have dependencies but
        // which don't have jars. We still need them in the graph so that
        // everything gets wired up properly. We _could_ attempt to find
        // the transitive dependencies and wire those into the lock file
        // neatly, but we're instead going to go for the clunkier solution
        // of recording that this dep has no outputs. When we read the lock
        // file, we'll generate an empty `java_library` which aggregates the
        // dependencies.
        skippedDeps.add(coord);
      }

      // If there's a file, make a note of where it came from
      String file = (String) coursierDep.get("file");
      if (file != null) {
        fileMappings.put(coords, file);
      }

      String classifier = coords.getClassifier();
      if (classifier == null || classifier.isEmpty()) {
        classifier = "jar";
      }
      shasums
          .computeIfAbsent(altKey, k -> new TreeMap<>())
          .put(classifier, (String) coursierDep.get("sha256"));

      // To keep the lock file small, for javadocs and sources we stop here. We have enough
      // information already
      if (!("javadoc".equals(coords.getClassifier()) || "sources".equals(coords.getClassifier()))) {
        artifacts.add(coords.toString());

        @SuppressWarnings("unchecked")
        Collection<String> mirrorUrls =
            (Collection<String>) coursierDep.getOrDefault("mirror_urls", new TreeSet<>());
        for (String mirrorUrl : mirrorUrls) {
          for (String repo : repositories) {
            if (mirrorUrl.startsWith(repo)) {
              repos.get(repo).add(key);
            }
          }
        }

        @SuppressWarnings("unchecked")
        Collection<String> depCoords =
            (Collection<String>) coursierDep.getOrDefault("directDependencies", new TreeSet<>());
        Set<String> directDeps =
            depCoords.stream()
                .map(Coordinates::new)
                .map(c -> mappings.getOrDefault(c, c))
                .map(Coordinates::asKey)
                .collect(Collectors.toCollection(TreeSet::new));

        if (!directDeps.isEmpty()) {
          deps.computeIfAbsent(key, k -> new TreeSet<>()).addAll(directDeps);
        }

        @SuppressWarnings("unchecked")
        Collection<String> depPackages =
            (Collection<String>) coursierDep.getOrDefault("packages", new TreeSet<>());
        if (!depPackages.isEmpty()) {
          packages.computeIfAbsent(key, k -> new TreeSet<>()).addAll(depPackages);
        }
      }
    }

    // Insertion order matters
    Map<String, Object> v2Lock = new LinkedHashMap<>();
    // The bit people care about
    v2Lock.put("artifacts", artifacts);
    // The other bits
    v2Lock.put("dependencies", deps);
    if (!skippedDeps.isEmpty()) {
      v2Lock.put("skipped", skippedDeps);
    }
    v2Lock.put("packages", packages);
    if (isUsingM2Local) {
      v2Lock.put("m2local", isUsingM2Local);
    }
    v2Lock.put("repositories", repos);
    // The bits that only a machine really cares about
    v2Lock.put("shasums", shasums);
    // And we need a version in there
    v2Lock.put("version", "2");

    // Metadata we will discard eventually
    v2Lock.put("files", fileMappings);

    return v2Lock;
  }

  private Map<String, Object> readDepTree() {
    try (Reader reader = Files.newBufferedReader(unsortedJson)) {
      return new Gson().fromJson(reader, new TypeToken<Map<String, Object>>() {}.getType());
    } catch (IOException e) {
      throw new UncheckedIOException(e);
    }
  }

  /**
   * Provide mappings from coordinates that are incorrect in the original lock file.
   *
   * <p>It turns out that coursier will sometimes claim that a regular set of coordinates is, in
   * fact, for a different extension (typically `aar`). The v2 lock file format relies on the
   * coordinates to determine the path to the artifact, so this kind of nonsense <i>will not
   * stand</i>. Go through all the coordinates in the file and make sure that the coordinate matches
   * the output path. If it doesn't, work out the correct coordinate and provide a mapping.
   *
   * @return a mapping of {@link Coordinates} from the dep tree to the correct {
   * @link Coordinates}.
   */
  private Map<Coordinates, Coordinates> deriveCoordinateMappings(Map<String, Object> depTree) {
    Map<Coordinates, Coordinates> toReturn = new HashMap<>();

    @SuppressWarnings("unchecked")
    Collection<Map<String, Object>> coursierDeps =
        (Collection<Map<String, Object>>) depTree.get("dependencies");
    for (Map<String, Object> coursierDep : coursierDeps) {
      Coordinates coord = new Coordinates((String) coursierDep.get("coord"));
      String expectedPath = new MavenRepositoryPath(coord).getPath();
      String file = (String) coursierDep.get("file");

      if (file == null) {
        toReturn.put(coord, coord);
        continue;
      }

      // Files may be URL encoded. Decode
      try {
        file = URLDecoder.decode(file, UTF_8.toString());
      } catch (UnsupportedEncodingException e) {
        throw new RuntimeException(e);
      }

      if (file.endsWith(expectedPath)) {
        toReturn.put(coord, coord);
        continue;
      }

      // The path of the output does not match the expected path. Attempt to rewrite.
      // Assume that the group and artifact IDs are correct, otherwise, we have real
      // problems.

      // The expected path looks something like:
      // "[group]/[artifact]/[version]/[artifact]-[version](-[classifier])(.[extension])"
      String prefix = coord.getGroupId().replace(".", "/") + "/" + coord.getArtifactId() + "/";

      int index = file.indexOf(prefix);
      if (index == -1) {
        throw new IllegalArgumentException(
            String.format(
                "Cannot determine actual coordinates for %s. Current coordinates are %s",
                file, coord));
      }
      String pathSubstring = file.substring(index + prefix.length());

      // The next part of the string should be the version number
      index = pathSubstring.indexOf("/");
      if (index == -1) {
        throw new IllegalArgumentException(
            String.format(
                "Cannot determine version number from %s. Current coordinates are %s",
                file, coord));
      }
      String version = pathSubstring.substring(0, index);

      // After the version, there should be nothing left but a file name
      pathSubstring = pathSubstring.substring(version.length() + 1);

      // Now we know the version, we can calculate the expected file name. For now, ignore
      // the fact that there may be a classifier. We're going to derive that if necessary.
      String expectedFileName = coord.getArtifactId() + "-" + version;

      index = pathSubstring.indexOf(expectedFileName);
      if (index == -1) {
        throw new IllegalArgumentException(
            String.format(
                "Expected file name (%s) not found in path (%s). Current coordinates are %s",
                expectedFileName, file, coord));
      }

      String classifier = "";
      String extension = "";
      String remainder = pathSubstring.substring(expectedFileName.length());

      if (remainder.isEmpty()) {
        throw new IllegalArgumentException(
            String.format(
                "File does not appear to have a suffix. %s. Current coordinates are %s",
                file, coord));
      }

      if (remainder.charAt(0) == '-') {
        // We have a classifier
        index = remainder.lastIndexOf('.');
        if (index == -1) {
          throw new IllegalArgumentException(
              String.format(
                  "File does not appear to have a suffix. %s. Current coordinates are %s",
                  file, coord));
        }
        classifier = remainder.substring(1, index);
        extension = remainder.substring(index + 1);
      } else if (remainder.charAt(0) == '.') {
        // We have an extension
        extension = remainder.substring(1);
      } else {
        throw new IllegalArgumentException(
            String.format(
                "Unable to determine classifier and extension from %s. Current coordinates are %s",
                file, coord));
      }

      toReturn.put(
          coord,
          new Coordinates(
              coord.getGroupId(), coord.getArtifactId(), extension, classifier, version));
    }

    return toReturn;
  }

  private boolean isSkipDep(Map<String, Object> coursierDep) {
    @SuppressWarnings("unchecked")
    String coord = (String) coursierDep.get("coord");

    if (coord == null) {
      return true;
    }
    if (!coursierDep.containsKey("sha256")) {
      return true;
    }
    if (!coursierDep.containsKey("file")
        || coursierDep.get("file") == null
        || "".equals(coursierDep.get("file"))) {
      return true;
    }

    return false;
  }
}
