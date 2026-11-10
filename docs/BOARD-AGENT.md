# Board reports and online firmware discovery

Implemented: a read-only Linux prototype, authenticated backend catalog-check endpoint
and an online check card in **Updates**. Neither a flash installer nor a bootable
AirLink firmware image is implemented. The probe is not installed or hardware-tested
on CRS112 or netPower. It does not supply missing board, Ethernet/switch or PoE drivers.

## Dashboard and current RouterOS devices

Connect to the backend and open **Updates → Check board & online catalog**. The backend
uses its existing verified SSH monitoring session and exact model/architecture/port
checks. It requires a non-stale snapshot no older than 60 seconds; PoE and monitoring
remain serialized on each device. Flutter pauses its polling/PoE actions during the
request and discards results after a connection change.

The response contains reported model, architecture, optional board revision, RouterOS
version and observation time. Installed AirLink version remains unavailable for RouterOS.
The online request fetches a fixed public catalog and sends no board data, credentials,
serial numbers, MACs or local IPs. The catalog server sees the normal source IP of the
HTTPS connection. Demo preview makes no board or online request.

## Linux prototype: startup and periodic checks

On an **existing Linux development system**, with Python 3.9+ and trusted system CA
certificates, use the project source:

```sh
PYTHONPATH=backend python3 -m airlink.board_probe
PYTHONPATH=backend python3 -m airlink.board_probe --check-online
PYTHONPATH=backend python3 -m airlink.board_probe --check-online --watch --interval 21600
```

The last command reports immediately, then every six hours until stopped. The supported
interval is 300–86400 seconds. It emits one JSON object per cycle to stdout. It opens no
network listener, executes no shell commands and never mounts, flashes, reboots or
changes IP/PoE settings. `--check-online` is explicit; the default is local reads only.

Generic Linux/systemd staging and isolated runtime tests are now available in
[the integration workspace](../firmware/integration/linux/README.md). The service unit
waits for network availability and supervises the reporting process. No service has been
installed or enabled on a switch, and no switch init system is presumed. For a future
image, integrate with that board's verified init system. On-target Python/runtime and CA
footprint, persistent status storage, boot activation and transport to Flutter remain unfinished;
in particular Python's suitability for these boards' flash space is unverified. This is
a portable prototype, not a decision to package Python into switch firmware.

Read sources are bounded device-tree `model`/`compatible`, `/proc/cpuinfo`,
`/proc/meminfo`, `/proc/uptime` and `/etc/os-release`. OS values are parsed as text,
never executed. Available RAM is bytes; uptime is seconds. Unavailable values are null.
No serial/MAC/hostname is collected. The model matcher recognizes only explicit supported
product labels, and MIPS byte order is checked. Architecture or board names alone never
prove compatibility. Board revision is deliberately null: a verified Linux mapping for
each physical revision is still missing. `identity_verified` is always false for this
prototype. Only `ID=airlink` permits `VERSION_ID` to be reported as the AirLink version.

## Online catalog and trust limits

Catalog URL:
`https://raw.githubusercontent.com/safin97/airlink-switch-manager/main/firmware/catalog.json`

`firmware/catalog.json` currently contains **no releases**, because no verified switch
firmware exists. Host application ZIPs and Flutter `.bin` assets are never candidates.
The catalog has schema version 1, a timezone-aware `generated_at` and `releases` list.
Future records require exact product/architecture/revision, stable numeric `major.minor.patch`
version, SHA-256, image size and a `.bin` release URL in this same GitHub repository.
Those fields are declarations, not hardware certification. No binaries are downloaded.

HTTPS uses hostname/certificate validation; redirects and caller-supplied URLs are
rejected, no credentials/proxy environment are used, and responses are capped at 64 KiB.
Socket operations time out after five seconds, with a 15-second body-loop deadline;
OS DNS-resolution timing is platform-dependent. Duplicate keys, invalid schemas,
malformed versions and off-repository asset URLs fail closed. Checks are serialized
and cached/backed off for 60 seconds per process. Failed checks retain the last successful
retrieval time but never offer a cached candidate as currently available.

Catalog metadata older than seven days or more than five minutes ahead of the local
clock is marked stale. Maintain the catalog timestamp only after review; a device needs
an accurate clock for TLS and age checks. Version comparisons are numeric, and candidates
must match model, architecture and revision exactly. Unknown installed version prevents
an up-to-date claim. Older or equal listed versions never trigger a downgrade.

This is **unsigned discovery metadata**, not a cryptographically verified update feed.
The separate [offline verifier](FIRMWARE-VERIFICATION.md) is not integrated into this
catalog or the minimal Linux probe overlay.
All responses set `signature_verified=false` and `installation_allowed=false`. Signed
manifests, pinned trust keys, rollback protection, image validation, authenticated install
permissions, explicit confirmation and tested recovery remain unfinished. Online
discovery does not unblock any of the board-support or flashing requirements.

References: [Python HTTPS verification](https://docs.python.org/3/library/http.client.html)
and [Linux device-tree ABI](https://github.com/torvalds/linux/blob/master/Documentation/ABI/testing/sysfs-firmware-ofw).
