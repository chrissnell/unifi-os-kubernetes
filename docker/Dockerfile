# UniFi OS Server application image.
#
# This Dockerfile is a thin wrapper over the "uosserver" base image, which is
# extracted directly from Ubiquiti's official self-hosted UniFi OS Server
# installer (the .run file from fw-update.ubnt.com). The base image is built
# by .github/workflows/extract-linux-{amd64,arm64}.yaml and combined into a
# multi-arch manifest by build-uosserver.yaml.
#
# UOS_SERVER_VERSION must match the upstream Ubiquiti release that produced
# the referenced uosserver tag. Both fields are bumped together by the
# release-check workflow.

ARG UOSSERVER_IMAGE=ghcr.io/chrissnell/uosserver
ARG UOSSERVER_TAG=0.0.54-multiarch

FROM ${UOSSERVER_IMAGE}:${UOSSERVER_TAG}

LABEL org.opencontainers.image.source="https://github.com/chrissnell/unifi-os-kubernetes"
LABEL org.opencontainers.image.description="UniFi OS Server packaged for Docker and Kubernetes"
LABEL org.opencontainers.image.licenses="MIT"

ENV UOS_SERVER_VERSION="5.0.6"

# Network application version. Bumped automatically by the
# network-app-release-check workflow whenever Ubiquiti's FUS publishes a
# newer release-channel `unifi` paired with this UOS_SERVER_VERSION.
ARG NETWORK_APP_VERSION=10.3.55-34128-1
ENV NETWORK_APP_VERSION=${NETWORK_APP_VERSION}

# Bake the Network app into the image so first boot doesn't show the
# "Install Network App" prompt. Uses Ubiquiti's own `uos` CLI so the
# package, signing, and dependency resolution match exactly what UOS
# would do at runtime.
#
# - policy-rc.d short-circuits service-start attempts in postinst;
#   systemd isn't running during `docker build`.
# - SKIP_DPKG_CACHE=yes suppresses the ubnt-dpkg-cache post-invoke hook
#   so we don't bake a /persistent/dpkg cache into the image (it would
#   be shadowed by the data PVC at runtime anyway).
RUN set -eux; \
    printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d; \
    chmod +x /usr/sbin/policy-rc.d; \
    SKIP_DPKG_CACHE=yes \
      /usr/bin/uos runnable install --version "${NETWORK_APP_VERSION}" unifi; \
    rm /usr/sbin/policy-rc.d; \
    rm -rf /var/lib/apt/lists/*

# systemd inside the container expects SIGRTMIN+3 to perform a clean shutdown.
STOPSIGNAL SIGRTMIN+3

COPY entrypoint.sh /usr/local/bin/uos-entrypoint.sh
RUN chmod +x /usr/local/bin/uos-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/uos-entrypoint.sh"]
