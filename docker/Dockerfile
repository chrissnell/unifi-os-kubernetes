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

# `uos runnable install` reads /usr/lib/version (firmware version file).
# Ubiquiti's installer writes that file on the host, not inside the image —
# entrypoint.sh recreates it at runtime, but we also need it at build time
# for the bake step below. Match the entrypoint's format. Same for
# /usr/lib/platform if it's missing in upstream.
RUN set -eux; \
    echo "UOSSERVER.0000000.${UOS_SERVER_VERSION}.0000000.000000.0000" > /usr/lib/version; \
    if [ ! -s /usr/lib/platform ]; then \
        case "$(dpkg --print-architecture)" in \
            amd64) echo linux-x64 > /usr/lib/platform ;; \
            arm64) echo arm64 > /usr/lib/platform ;; \
            *)     echo "linux-$(dpkg --print-architecture)" > /usr/lib/platform ;; \
        esac; \
    fi

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

# Point unifi-core's discovery client at localhost. Upstream defaults to
# host.docker.internal, which doesn't resolve inside a Kubernetes pod and
# previously required a postStart `/etc/hosts` hack in the chart.
RUN if [ -f /etc/default/unifi-core_advanced ]; then \
      sed -i 's|host\.docker\.internal|localhost|g' /etc/default/unifi-core_advanced; \
    fi

# uos-discovery-client and uos-agent ship as stub binaries — they exit
# immediately ("Stub package") with no real functionality. Both units use
# Restart=always + StartLimitIntervalSec=0, so the stubs restart-storm and
# fill the journal with noise. Drop-in overrides suppress the loop.
RUN mkdir -p \
        /etc/systemd/system/uos-discovery-client.service.d \
        /etc/systemd/system/uos-agent.service.d \
    && printf '[Service]\nRestart=no\n' \
        > /etc/systemd/system/uos-discovery-client.service.d/no-restart.conf \
    && printf '[Service]\nRestart=no\n' \
        > /etc/systemd/system/uos-agent.service.d/no-restart.conf

# Discovery shim — minimal Node HTTP server on 127.0.0.1:11002 that
# satisfies unifi-core's discovery polls so it stops logging
# "ECONNREFUSED 127.0.0.1:11002" / "Failed to fetch network interfaces"
# every few seconds. See discovery-shim.js for protocol details.
COPY discovery-shim.js /usr/local/lib/uos-discovery-shim/shim.js
COPY uos-discovery-shim.service /etc/systemd/system/uos-discovery-shim.service
RUN ln -sf /etc/systemd/system/uos-discovery-shim.service \
        /etc/systemd/system/multi-user.target.wants/uos-discovery-shim.service

# systemd inside the container expects SIGRTMIN+3 to perform a clean shutdown.
STOPSIGNAL SIGRTMIN+3

COPY entrypoint.sh /usr/local/bin/uos-entrypoint.sh
RUN chmod +x /usr/local/bin/uos-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/uos-entrypoint.sh"]
