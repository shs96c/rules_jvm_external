package com.github.bazelbuild.rules_jvm_external.resolver.gradle.plugin;

import org.gradle.api.artifacts.result.ResolvedComponentResult;
import org.gradle.api.artifacts.result.ResolvedDependencyResult;
import org.gradle.api.artifacts.result.ResolvedVariantResult;
import org.gradle.api.attributes.Attribute;
import org.gradle.api.attributes.AttributeContainer;
import org.gradle.api.attributes.Category;

import java.io.File;
import java.util.Objects;

import static org.gradle.api.attributes.Category.CATEGORY_ATTRIBUTE;

class ResolutionData {
    private final ResolvedComponentResult result;
    private final File file;

    public ResolutionData(ResolvedComponentResult result, File file) {
        this.result = result;
        this.file = file;
    }

    public ResolvedComponentResult getResult() {
        return result;
    }

    public File getFile() {
        return file;
    }

    private boolean isLibraryComponent() {
        for (ResolvedVariantResult variant : result.getVariants()) {
            AttributeContainer attributes = variant.getAttributes();

            Attribute<?> category = attributes.keySet().stream()
                    .filter(a -> CATEGORY_ATTRIBUTE.getName().equals(a.getName()))
                    .findFirst()
                    .orElse(null);

            if (category == null) {
                continue;
            }

            Object attribute = attributes.getAttribute(category);
            if (Category.LIBRARY.equals(attribute)) {
                continue;
            }
            return false;
        }
        return true;
    }

    private boolean isPlatformComponent() {
        for (ResolvedVariantResult variant : result.getVariants()) {
            AttributeContainer attributes = variant.getAttributes();

            Attribute<?> category = attributes.keySet().stream()
                    .filter(a -> CATEGORY_ATTRIBUTE.getName().equals(a.getName()))
                    .findFirst()
                    .orElse(null);

            if (category == null) {
                continue;
            }

            Object attribute = attributes.getAttribute(category);
            if (Category.REGULAR_PLATFORM.equals(attribute) || Category.ENFORCED_PLATFORM.equals(attribute)) {
                return true;
            }
        }
        return false;
    }

    @Override
    public String toString() {
        return "ResolutionData{" +
                "result=" + result.getId() +
                ", file=" + (file == null ? "null" : file.getName()) +
                '}';
    }

    @Override
    public boolean equals(Object o) {
        if (!(o instanceof ResolutionData)) {
            return false;
        }
        ResolutionData that = (ResolutionData) o;
        return Objects.equals(result, that.result) && Objects.equals(file, that.file);
    }

    @Override
    public int hashCode() {
        return Objects.hash(result, file);
    }
}
