package com.github.bazelbuild.rules_jvm_external.coursier;

import com.github.bazelbuild.rules_jvm_external.Coordinates;
import com.github.bazelbuild.rules_jvm_external.resolver.DependencyInfo;

import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import java.util.TreeSet;
import java.util.stream.Collectors;

public class V2Format {

    private final Set<String> repositories;

    public V2Format(Set<String> repositories) {
        this.repositories = repositories;
    }

    public Map<String, Object> render(Set<DependencyInfo> infos) {
        boolean isUsingM2Local =
                repositories.stream().map(String::toLowerCase).anyMatch(repo -> repo.equals("m2local/"));

        Set<String> artifacts = new TreeSet<>();
        Map<String, Set<String>> deps = new TreeMap<>();
        Map<String, Map<String, String>> shasums = new TreeMap<>();
        Map<String, Set<String>> packages = new TreeMap<>();
        // Insertion order matters
        Map<String, Set<String>> repos = new LinkedHashMap<>();
        repositories.forEach(r -> repos.put(r, new TreeSet<>()));

        Map<String, Object> v2Lock = new LinkedHashMap<>();

        infos.forEach(info -> {
            Coordinates coords = info.getCoordinates();
            String key = coords.asKey();
            String shasumKey = coords.setClassifier("jar").asKey();

            artifacts.add(coords.toString());
            deps.computeIfAbsent(
                    key, k -> new TreeSet<>()).addAll(
                    info.getDependencies().stream()
                            .map(Object::toString)
                            .collect(Collectors.toCollection(TreeSet::new)));
            packages.computeIfAbsent(key, k -> new TreeSet<>()).addAll(info.getPackages());

            Map<String, String> shas = shasums.computeIfAbsent(shasumKey, k -> new TreeMap<>());
            String classifier = coords.getClassifier();
            if (classifier == null || classifier.isEmpty()) {
                classifier = "jar";
            }
            shas.put(classifier, info.getSha256());
            if (info.getJavadocSha256() != null) {
                shas.put("javadoc", info.getJavadocSha256());
            }
            if (info.getSourceSha256() != null) {
                shas.put("sources", info.getSourceSha256());
            }
        });

        v2Lock.put("artifacts", artifacts);
        v2Lock.put("dependencies", removeEmptyItems(deps));
        v2Lock.put("packages", removeEmptyItems(packages));
        if (isUsingM2Local) {
            v2Lock.put("m2local", true);
        }
        v2Lock.put("repositories", repos);
        v2Lock.put("shasums", shasums);
        v2Lock.put("version", "2");

        return v2Lock;
    }

    private <K, V extends Collection> Map<K, V> removeEmptyItems(Map<K, V> input) {
        return input.entrySet().stream()
                .filter(e -> !e.getValue().isEmpty())
                .collect(Collectors.toMap(
                        Map.Entry::getKey,
                        Map.Entry::getValue,
                        (l, r) -> {
                            l.addAll(r);
                            return l;
                        },
                        TreeMap::new));
    }
}
