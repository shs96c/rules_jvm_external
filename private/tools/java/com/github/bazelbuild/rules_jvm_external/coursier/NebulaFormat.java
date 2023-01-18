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

public class NebulaFormat {
    private final Set<String> repositories;

    public NebulaFormat(Set<String> repositories) {
        this.repositories = repositories;
    }

    public Map<String, Object> render(Set<DependencyInfo> infos) {
        boolean isUsingM2Local =
                repositories.stream().map(String::toLowerCase).anyMatch(repo -> repo.equals("m2local/"));

        Map<String, Map<String, Object>> artifacts = new TreeMap<>();
        Map<String, Set<String>> deps = new TreeMap<>();
        Map<String, Set<String>> packages = new TreeMap<>();
        Map<String, Set<String>> repos = new LinkedHashMap<>();
        repositories.forEach(r -> repos.put(r, new TreeSet<>()));

        infos.forEach(info -> {
            Coordinates coords = info.getCoordinates();
            String key = coords.asKey();
            String shortKey = coords.setClassifier("jar").asKey();

            Map<String, Object> artifactValue = artifacts.computeIfAbsent(shortKey, k -> new TreeMap<>());
            artifactValue.put("version", coords.getVersion());

            String classifier = coords.getClassifier();
            if (classifier == null || classifier.isEmpty()) {
                classifier = "jar";
            }
            @SuppressWarnings("unchecked")
            Map<String, String> shasums = (Map<String, String>) artifactValue.computeIfAbsent("shasums", k -> new TreeMap<>());
            shasums.put(classifier, info.getSha256());
            if (info.getJavadocSha256() != null) {
                shasums.put("javadoc", info.getJavadocSha256());
            }
            if (info.getSourceSha256() != null) {
                shasums.put("sources", info.getSourceSha256());
            }

            deps.put(key, info.getDependencies().stream().map(Object::toString).collect(Collectors.toCollection(TreeSet::new)));
            packages.put(key, info.getPackages());

            
        });

        Map<String, Object> lock = new LinkedHashMap<>();
        lock.put("artifacts", artifacts);
        lock.put("dependencies", removeEmptyItems(deps));
        lock.put("packages", removeEmptyItems(packages));
        if (isUsingM2Local) {
            lock.put("m2local", true);
        }
        lock.put("repositories", repos);
        lock.put("version", "2");

        return lock;
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
