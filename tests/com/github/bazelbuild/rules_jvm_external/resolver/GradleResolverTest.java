package com.github.bazelbuild.rules_jvm_external.resolver;

import com.github.bazelbuild.rules_jvm_external.resolver.events.EventListener;
import com.github.bazelbuild.rules_jvm_external.resolver.gradle.GradleResolver;
import com.github.bazelbuild.rules_jvm_external.resolver.netrc.Netrc;
import org.gradle.internal.logging.slf4j.OutputEventListenerBackedLoggerContext;
import org.slf4j.LoggerFactory;

import java.util.ServiceLoader;

public class GradleResolverTest extends ResolverTestBase {

  @Override
  protected Resolver getResolver(Netrc netrc, EventListener listener) {
    return new GradleResolver(netrc, listener);
  }
}
