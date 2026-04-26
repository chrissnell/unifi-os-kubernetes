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

# systemd inside the container expects SIGRTMIN+3 to perform a clean shutdown.
STOPSIGNAL SIGRTMIN+3

COPY entrypoint.sh /usr/local/bin/uos-entrypoint.sh
RUN chmod +x /usr/local/bin/uos-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/uos-entrypoint.sh"]
