package com.github.bazelbuild.rules_jvm_external.resolver.gradle;

import org.gradle.internal.logging.slf4j.OutputEventListenerBackedLoggerContext;
import org.gradle.internal.time.Time;
import org.slf4j.ILoggerFactory;
import org.slf4j.IMarkerFactory;
import org.slf4j.helpers.BasicMDCAdapter;
import org.slf4j.helpers.BasicMarkerFactory;
import org.slf4j.spi.MDCAdapter;
import org.slf4j.spi.SLF4JServiceProvider;

/**
 * Used to ensure that slf4j is properly configured for use with Gradle.
 * Normally we would want to register this class as a service for use with
 * the `ServiceLoader` approach to configuration that slf4j uses, but we only
 * want this implementation to be used if we're using the Gradle resolver. To
 * ensure that this is only used in that case, the `GradleResolver` will add
 * this to the slf4j config if selected.
 */
public class GradleSlf4jProvider implements SLF4JServiceProvider {

    // Deliberately not `final` because apparently the internals of slf4j need
    // this not to be inlined.
    public static String REQUESTED_API_VERSION = "2.0.99";

    private ILoggerFactory factory;
    private IMarkerFactory markerFactory;
    private MDCAdapter mdcAdapter;

    @Override
    public ILoggerFactory getLoggerFactory() {
        return factory;
    }

    @Override
    public IMarkerFactory getMarkerFactory() {
        return markerFactory;
    }

    @Override
    public MDCAdapter getMDCAdapter() {
        return mdcAdapter;
    }

    @Override
    public String getRequestedApiVersion() {
        return REQUESTED_API_VERSION;
    }

    @Override
    public void initialize() {
        factory = new OutputEventListenerBackedLoggerContext(Time.clock());
        markerFactory = new BasicMarkerFactory();
        mdcAdapter = new BasicMDCAdapter();
    }
}
