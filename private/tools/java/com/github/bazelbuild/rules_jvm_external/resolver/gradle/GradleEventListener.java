package com.github.bazelbuild.rules_jvm_external.resolver.gradle;

import com.github.bazelbuild.rules_jvm_external.resolver.events.DownloadEvent;
import com.github.bazelbuild.rules_jvm_external.resolver.events.EventListener;
import java.util.Objects;
import org.gradle.tooling.events.ProgressEvent;
import org.gradle.tooling.events.ProgressListener;
import org.gradle.tooling.events.download.FileDownloadFinishEvent;
import org.gradle.tooling.events.download.FileDownloadStartEvent;

class GradleEventListener implements ProgressListener {

  private static final String DOWNLOAD = "Download ";
  private final EventListener listener;

  public GradleEventListener(EventListener listener) {
    this.listener = Objects.requireNonNull(listener);
  }

  @Override
  public void statusChanged(ProgressEvent pe) {
    if (pe instanceof FileDownloadStartEvent) {
      String name = pe.getDescriptor().getName();
      if (name == null) {
        return;
      }
      if (name.startsWith(DOWNLOAD)) {
        name = name.substring(DOWNLOAD.length());
      }

      listener.onEvent(new DownloadEvent(DownloadEvent.Stage.STARTING, name));
    } else if (pe instanceof FileDownloadFinishEvent) {
      String name = pe.getDescriptor().getName();
      if (name == null) {
        return;
      }
      if (name.startsWith(DOWNLOAD)) {
        name = name.substring(DOWNLOAD.length());
      }
      listener.onEvent(new DownloadEvent(DownloadEvent.Stage.COMPLETE, name));
    }
  }
}
