#!/bin/sh
# Locate a Node.js runtime and start the discovery shim (shim.js).
#
# The shim needs Node. The UniFi OS image ships one because unifi-core is a
# Node app, but the binary is not guaranteed to live at /usr/bin/node — its
# exact path varies across UOS Server releases. The systemd unit used to
# hardcode /usr/bin/node, so on images where node sits elsewhere the service
# failed with 203/EXEC and restart-stormed the journal (GitHub #10).
#
# Resolve node at runtime instead. If none can be found, log why and exit 0
# so systemd does not restart-loop: the shim is only a cosmetic nicety (it
# silences unifi-core's discovery poll log spam), so its absence must never
# storm the journal. Set DISCOVERY_SHIM_NODE to override the search.
set -eu

SHIM=/usr/local/lib/uos-discovery-shim/shim.js

for candidate in \
    "${DISCOVERY_SHIM_NODE:-}" \
    node \
    /usr/bin/node \
    /usr/local/bin/node \
    /usr/share/unifi-core/node \
    /usr/lib/unifi-core/node
do
    [ -n "$candidate" ] || continue
    node_path="$(command -v "$candidate" 2>/dev/null || true)"
    [ -n "$node_path" ] && [ -x "$node_path" ] || continue
    echo "uos-discovery-shim: using node at $node_path"
    exec "$node_path" "$SHIM"
done

echo "uos-discovery-shim: no node runtime found; discovery shim disabled." >&2
echo "uos-discovery-shim: unifi-core discovery polls will log harmless ECONNREFUSED noise." >&2
exit 0
