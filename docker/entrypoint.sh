#!/bin/bash
# UniFi OS Server container entrypoint.
#
# Prepares per-container state (UUID, version string, log/data dirs) and then
# hands control to systemd, which boots the bundled UOS service stack
# (mongodb, postgresql, rabbitmq, nginx, java network app, go services, ...).

set -euo pipefail

DATA_DIR="${UOS_DATA_DIR:-/data}"

# 1. Persist a stable UOS_UUID across container restarts.
if [ ! -f "$DATA_DIR/uos_uuid" ]; then
    if [ -n "${UOS_UUID:-}" ]; then
        echo "Persisting supplied UOS_UUID=$UOS_UUID"
        printf '%s' "$UOS_UUID" > "$DATA_DIR/uos_uuid"
    else
        RAW_UUID=$(cat /proc/sys/kernel/random/uuid)
        # Force the version nibble to 5 so UOS treats the id as a v5 UUID.
        UOS_UUID=$(echo "$RAW_UUID" | sed 's/./5/15')
        echo "Generated UOS_UUID=$UOS_UUID"
        printf '%s' "$UOS_UUID" > "$DATA_DIR/uos_uuid"
    fi
fi

# 2. Write the UOS version string the bundled services expect.
echo "Setting UOS_SERVER_VERSION=${UOS_SERVER_VERSION}"
echo "UOSSERVER.0000000.${UOS_SERVER_VERSION}.0000000.000000.0000" > /usr/lib/version

# 3. Map dpkg arch to UOS firmware platform.
ARCH="$(dpkg --print-architecture)"
case "$ARCH" in
    amd64) FIRMWARE_PLATFORM=linux-x64 ;;
    arm64) FIRMWARE_PLATFORM=arm64 ;;
    *)
        echo "Unsupported architecture: $ARCH" >&2
        exit 1
        ;;
esac
echo "Setting FIRMWARE_PLATFORM=$FIRMWARE_PLATFORM"
echo "$FIRMWARE_PLATFORM" > /usr/lib/platform

# 4. UOS expects an eth0; alias it to tap0 if present (macvlan setups).
if [ ! -d /sys/devices/virtual/net/eth0 ] && [ -d /sys/devices/virtual/net/tap0 ]; then
    ip link add name eth0 link tap0 type macvlan
    ip link set eth0 up
fi

# 5. Ensure runtime directories exist with correct ownership.
ensure_dir() {
    local path="$1" owner="$2" mode="$3"
    if [ ! -d "$path" ]; then
        mkdir -p "$path"
    fi
    chown -R "$owner" "$path"
    chmod "$mode" "$path"
}

ensure_dir /var/log/nginx     nginx:nginx     755
ensure_dir /var/log/mongodb   mongodb:mongodb 755
ensure_dir /var/log/rabbitmq  rabbitmq:rabbitmq 755
chown -R mongodb:mongodb /var/lib/mongodb || true

# 6. Synology-specific systemd unit overrides (DSM cgroup quirks).
SYS_VENDOR="/sys/class/dmi/id/sys_vendor"
if { [ -f "$SYS_VENDOR" ] && grep -q Synology "$SYS_VENDOR"; } \
    || [ "${HARDWARE_PLATFORM:-}" = "synology" ]; then
    echo "Synology hardware detected, applying systemd overrides"

    mkdir -p /etc/systemd/system/postgresql@14-main.service.d
    cat > /etc/systemd/system/postgresql@14-main.service.d/override.conf <<EOF
[Service]
PIDFile=
EOF

    mkdir -p /etc/systemd/system/rabbitmq-server.service.d
    cat > /etc/systemd/system/rabbitmq-server.service.d/override.conf <<EOF
[Service]
Type=simple
EOF

    mkdir -p /etc/systemd/system/ulp-go.service.d
    cat > /etc/systemd/system/ulp-go.service.d/override.conf <<EOF
[Service]
Type=simple
EOF
fi

# 7. Optional: pin system_ip in unifi network properties.
UNIFI_SYSTEM_PROPERTIES="/var/lib/unifi/system.properties"
if [ -n "${UOS_SYSTEM_IP:-}" ]; then
    echo "Setting system_ip=$UOS_SYSTEM_IP in $UNIFI_SYSTEM_PROPERTIES"
    mkdir -p "$(dirname "$UNIFI_SYSTEM_PROPERTIES")"
    if [ -f "$UNIFI_SYSTEM_PROPERTIES" ] && grep -q '^system_ip=' "$UNIFI_SYSTEM_PROPERTIES"; then
        sed -i "s|^system_ip=.*|system_ip=$UOS_SYSTEM_IP|" "$UNIFI_SYSTEM_PROPERTIES"
    else
        echo "system_ip=$UOS_SYSTEM_IP" >> "$UNIFI_SYSTEM_PROPERTIES"
    fi
fi

exec /sbin/init
