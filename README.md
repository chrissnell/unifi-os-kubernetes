# unifi-os-kubernetes

Self-hosted **UniFi OS Server** on Docker and Kubernetes — built end-to-end
from the official Ubiquiti installer, with no third-party base images.

[![Build status](https://github.com/chrissnell/unifi-os-kubernetes/actions/workflows/build-image.yaml/badge.svg)](https://github.com/chrissnell/unifi-os-kubernetes/actions/workflows/build-image.yaml)
[![Release check](https://github.com/chrissnell/unifi-os-kubernetes/actions/workflows/release-check.yaml/badge.svg)](https://github.com/chrissnell/unifi-os-kubernetes/actions/workflows/release-check.yaml)

## What this is

[UniFi OS Server](https://blog.ui.com/article/introducing-unifi-os-server) is
Ubiquiti's modern self-hosted UniFi platform. It replaces the legacy UniFi
Network controller and ships a unified OS with the Network app, Identity Hub,
Site Magic SD-WAN, organizations, and more.

Ubiquiti distributes UOS only as a Linux self-extracting `.run` installer
that drops a Podman image on the host. This repository:

1. Polls Ubiquiti's official firmware API daily and detects new releases.
2. Runs the official installer on a GitHub-hosted runner, extracts the
   Podman image, and re-publishes it as `ghcr.io/chrissnell/uosserver` for
   both `linux/amd64` and `linux/arm64`.
3. Layers a small entrypoint on top to produce a runnable
   `ghcr.io/chrissnell/unifi-os-server` image.
4. Ships a clean, configurable **Helm chart** for running it in Kubernetes.

The image and chart are unaffiliated with Ubiquiti. UOS itself remains
Ubiquiti software under their EULA.

## Why a custom image

There is another commonly-used image out there, [`lemker/unifi-os-server`](https://github.com/lemker/unifi-os-server),
and I'm sure the image works fine, but its `uosserver` base layer is built and hosted on a
single contributor's GHCR account with no published Dockerfile (because the
image *cannot* be expressed as a Dockerfile — it comes from Ubiquiti's
installer). His project also has no Helm chart for Kubernetes users.

This project owns the full build pipeline so the supply chain is
auditable end-to-end, and it has a Helm chart to make it easier to install.

## Quick start (Docker)

```bash
docker run -d --name unifi-os-server \
  --cgroupns=host \
  --cap-add NET_ADMIN --cap-add NET_RAW \
  --tmpfs /run:exec --tmpfs /run/lock --tmpfs /tmp:exec \
  --tmpfs /var/lib/journal --tmpfs /var/opt/unifi/tmp:size=64m \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  -v unifi-data:/data \
  -v unifi-persistent:/persistent \
  -v unifi-srv:/srv \
  -v unifi-unifi:/var/lib/unifi \
  -v unifi-mongo:/var/lib/mongodb \
  -v unifi-log:/var/log \
  -p 11443:443 -p 8080:8080 -p 3478:3478/udp -p 10003:10003/udp \
  ghcr.io/chrissnell/unifi-os-server:latest
```

See [`docker/docker-compose.yaml`](docker/docker-compose.yaml) for a
fully-annotated reference.

## Quick start (Helm)

```bash
helm repo add unifi-os https://chrissnell.github.io/unifi-os-kubernetes
helm install unifi unifi-os/unifi-os-server \
  --namespace unifi --create-namespace \
  --set systemIp=unifi.example.com \
  --set service.type=LoadBalancer
```

Or directly from the repo (no chart-releaser needed):

```bash
git clone https://github.com/chrissnell/unifi-os-kubernetes
helm install unifi ./unifi-os-kubernetes/chart \
  --namespace unifi --create-namespace \
  -f my-values.yaml
```

Minimal `my-values.yaml`:

```yaml
systemIp: unifi.example.com

service:
  type: LoadBalancer
  loadBalancerIP: 10.0.0.10

persistence:
  data:
    storageClass: longhorn
    size: 30Gi
  mongo:
    storageClass: longhorn
    size: 10Gi
```

## Architecture

UOS is a **monolithic appliance image**. A single container runs systemd as
PID 1 and starts the bundled service stack:

| Component  | Role                            |
| ---------- | ------------------------------- |
| nginx      | TLS termination + web UI        |
| MongoDB    | Network app database            |
| PostgreSQL | UOS shell database              |
| RabbitMQ   | Inter-service messaging         |
| Java       | Network application             |
| Go         | Site Supervisor, Identity Hub, … |

There is no documented mechanism to point UOS at an external MongoDB. The
chart accepts that constraint and instead splits state across **three
optional PVCs** so the database, app data, and autobackups can be sized,
snapshotted, and restored independently:

| PVC       | Mount                          | Contains                                              |
| --------- | ------------------------------ | ----------------------------------------------------- |
| `data`    | `/persistent`, `/data`, `/srv`, `/var/lib/unifi`, `/var/log`, `/etc/rabbitmq/ssl` | UOS app state, configs, logs, RabbitMQ certs |
| `mongo`   | `/var/lib/mongodb`             | Bundled MongoDB datadir                               |
| `backups` | `/var/lib/unifi/data/backup`   | Network app autobackups (optional, off by default)    |

### Container requirements

Because UOS runs systemd, the container needs:

- `cgroupns=host` (or `--cgroup=host` in compose).
- `securityContext.privileged: true` and `NET_ADMIN` + `NET_RAW` caps.
- A bind mount of `/sys/fs/cgroup` from the host.
- tmpfs mounts for `/run`, `/run/lock`, `/tmp`, `/var/lib/journal`,
  `/var/opt/unifi/tmp`.

The chart wires all of this for you.

## Ports

| Port  | Proto | Purpose                          | Default in chart |
| ----- | ----- | -------------------------------- | ---------------- |
| 443   | TCP   | Web UI / API                     | enabled          |
| 8080  | TCP   | Device communication / inform    | enabled          |
| 3478  | UDP   | STUN                             | enabled          |
| 10003 | UDP   | L2 device discovery              | enabled          |
| 8443  | TCP   | Legacy Network app port          | optional         |
| 8444  | TCP   | Hotspot HTTPS portal             | optional         |
| 8880  | TCP   | Hotspot HTTP redirect            | optional         |
| 8881  | TCP   | Hotspot HTTP redirect            | optional         |
| 8882  | TCP   | Hotspot HTTP redirect            | optional         |
| 5005  | TCP   | RTP voice                        | optional         |
| 9543  | TCP   | Identity Hub                     | optional         |
| 6789  | TCP   | Mobile speedtest                 | optional         |
| 11084 | TCP   | Site Supervisor                  | optional         |
| 5671  | TCP   | AMQPS                            | optional         |
| 5514  | UDP   | Syslog                           | optional         |

Toggle each via `ports.<name>.enabled` in values.

## TLS via cert-manager

If you run cert-manager in your cluster, the chart can issue and rotate the
ingress TLS certificate for you:

```yaml
ingress:
  enabled: true
  host: unifi.example.com

certManager:
  enabled: true
  issuerRef:
    name: letsencrypt-prod         # ClusterIssuer name
    kind: ClusterIssuer
  dnsNames:
    - unifi.example.com
```

The chart creates a `Certificate` whose secret feeds the ingress automatically.
This controls the secret in front of the ingress only — UniFi's bundled nginx
keeps managing its own internal cert for device-facing TLS.

## Prometheus metrics

Enable the bundled [unpoller](https://github.com/unpoller/unpoller) exporter to
expose UOS metrics on `:9130`:

```yaml
unifiExporter:
  enabled: true
  config:
    apiKey: "your-uos-api-key"     # generate at Settings → Admins & Users
  serviceMonitor:
    enabled: true                  # if you run the Prometheus Operator
```

Three auth modes:

| Mode | Set | Notes |
|------|-----|-------|
| API key | `unifiExporter.config.apiKey` | Recommended on UOS 4+. |
| Username + password | `unifiExporter.config.username` + `password` | Local **Viewer** admin. |
| Pre-existing Secret | `unifiExporter.existingSecret.name` | Mount creds from ESO/Vault — chart reads `password` and/or `api-key` keys. |

The exporter URL defaults to the in-cluster webui Service
(`https://<release>-unifi-os-server-webui.<ns>.svc.cluster.local`); override
with `unifiExporter.config.url` if you want it to scrape a different endpoint.

## Restoring a legacy controller `.unf` backup

UOS's bundled Network app accepts `.unf` autobackups produced by older
self-hosted UniFi Network controllers (versions 5.x through 10.x).

1. Bring the chart up clean.
2. Wait for the Network app to be reachable in the UI.
3. Open **Network → Settings → System → Backup → Restore Backup**.
4. Upload the `.unf` file. UOS will load it into the bundled MongoDB.

There's no need to manipulate Mongo dumps directly.

### Re-adopting devices after a restore

After restoring a backup, your devices may still hold an adoption key
from the old controller and refuse to talk to UOS. They'll show up as
disconnected in the device list. When that happens:

1. **Factory-reset the device physically.** Hold the reset button until
   the LED blinks the reset pattern. Software reset from the old
   controller doesn't always clear the adoption state.
2. **Remove the stale entry from UOS.** In the UI, click the device, open
   its settings, and use the **Remove** button. This clears the old
   adoption record so the device can be re-adopted fresh.
3. **SSH to the device.** Default credentials are `ubnt` / `ubnt`:
   ```
   ssh ubnt@<device-ip>
   ```
4. **Point the device at UOS** with `set-inform`. The URL must be `http`
   (not `https`), on port `8080`, with the `/inform` path:
   ```
   set-inform http://<uos-host>:8080/inform
   ```
   `<uos-host>` is the IP or hostname your devices can reach UOS on —
   typically `systemIp` from your values.yaml, or the LoadBalancer IP of
   the `communication` (8080) service.
5. The device will show up under **Network → Devices** as **Pending
   Adoption** within a few seconds. Click **Adopt**. UOS pushes config
   and the device reboots.
6. If the device doesn't appear within a minute, re-run `set-inform`
   from the SSH session. Adoption sometimes drops the inform URL
   mid-flight and a second nudge brings it back.

Once adopted, UOS owns the inform URL and you won't need SSH again for
that device.

## Autobackups

UOS Network app autobackups land in `/var/lib/unifi/data/backup/autobackup/`
inside the container. By default that directory is on the `data` PVC, so
backups persist with the rest of UOS state.

For a stronger safety net, enable a separate `backups` PVC that overlays
just that path:

```yaml
persistence:
  backups:
    enabled: true
    storageClass: nfs-client
    size: 50Gi
```

Now autobackups can live on different (typically slower, cheaper, more
frequently-snapshotted) storage from the rest of UOS state. Snapshot or
replicate that PVC on its own schedule.

## Building locally

```bash
# Builds the application layer on top of the published uosserver base.
docker build -t local/unifi-os-server docker/

# Lint and render the chart.
helm lint chart/
helm template unifi chart/ > /tmp/render.yaml
```

## Update flow

`release-check.yaml` runs daily and:

1. Calls `https://fw-update.ubnt.com/api/firmware-latest` for the
   release-channel UOS version on each architecture.
2. Compares against the version pinned in `docker/Dockerfile`.
3. If new, runs the installer on amd64 and arm64 runners, extracts the
   Podman image, pushes per-arch tags, and stitches them into a multi-arch
   manifest.
4. Opens a PR bumping `UOSSERVER_TAG` and `UOS_SERVER_VERSION`.
5. Merging the PR triggers `build-image.yaml`, which publishes a new
   `unifi-os-server` tag.

## Network app updates

The image bakes in the Network app at the version Ubiquiti ships with
this UOS Server release. **Don't use the "Update" button in the UI.**

Network app upgrades happen by image bump. We check Ubiquiti daily and
publish a new [`unifi-os-server`](https://github.com/chrissnell/unifi-os-kubernetes/pkgs/container/unifi-os-server)
image when a new Network app is released. Pull the new image and restart
the pod.

If you do click the in-UI updater, the new `.deb` lands on the data PVC
and UOS replays it on every container start — so the upgrade sticks. The
cost is that your Network app version no longer matches what's pinned in
the image, and the next image bump won't downgrade you back. To roll back
to the image's version after an in-UI update:

```
kubectl exec -n unifi <pod> -- rm /persistent/dpkg/bullseye/packages/unifi_*.deb
kubectl rollout restart deploy/<release>
```

## Contributing

Issues and PRs welcome. Please don't open issues for UOS bugs themselves —
those should go to Ubiquiti.

## Credits

Several improvements in this repo (the discovery-shim approach for silencing
`uos-discovery-client` polling, `Restart=no` drop-ins for the stub
`uos-discovery-client` / `uos-agent` services, the bundled unpoller exporter,
and a few other touches) were inspired by prior work in
[ConnorsApps/unifi-os-helm](https://github.com/ConnorsApps/unifi-os-helm).
Thanks to [@ConnorsApps](https://github.com/ConnorsApps) for the ideas.

## License

This repo is MIT-licensed (see [LICENSE](LICENSE)). The packaged UOS
software is © Ubiquiti Inc. and remains under the
[Ubiquiti EULA](https://www.ui.com/legal/).
