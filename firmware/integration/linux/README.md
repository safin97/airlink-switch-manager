# Generic Linux development integration — not switch firmware

This overlay integrates the read-only AirLink probe into a **systemd Linux development
environment**. It does not select OpenWrt, systemd, Python or a flash layout for either
MikroTik board. Neither board currently has a verified kernel/root filesystem to accept
this overlay. The user confirmed that exact-board source and boot logs are unavailable.

The service starts after `network-online.target`, reports immediately and every six
hours, and restarts after a process failure. Catalog failures are reported as unavailable
and retried on the next cycle. The service uses a dynamic unprivileged user, no Linux
capabilities, read-only system files, private devices, and Python isolated mode. It has
no flash/network-setting/PoE write operations. JSON goes to the journal; no device data
or credentials are uploaded to the public catalog.

## Stage without installing

From the project root:

```sh
python3 scripts/stage_board_probe.py --output /tmp/airlink-probe-rootfs
```

The destination must be new. The script copies only the three required Python modules,
launcher, unit and this guide. `integration-manifest.json` records file sizes and hashes,
and explicitly marks the output as non-firmware. It does not copy private backend
configuration, enable services, install into `/usr`, or access a switch.

On a separately managed generic Linux development machine, a maintainer can place these
files at the staged paths and enable `airlink-board-probe.service` using that machine's
normal service-management process. That requires Python 3.9+, system CA certificates
and systemd with the specified hardening directives. This task does not perform that
installation. Installed code and units must be root-owned and not writable by the service
user. Do not copy the overlay onto RouterOS or package it as a MikroTik `.bin`.

## Reproduce the isolated Linux software test

Use a temporary Docker build context containing `Dockerfile.test` as `Dockerfile` and
the staged tree as `rootfs/`. Build it with a local tag such as
`airlink-switch-probe-integration:test`. Run without privileged access, host networking,
device passthrough, writable mounts or capabilities:

```sh
docker run --rm --read-only --network none --cap-drop ALL \
  --security-opt no-new-privileges airlink-switch-probe-integration:test
docker run --rm --read-only --cap-drop ALL --security-opt no-new-privileges \
  airlink-switch-probe-integration:test --check-online
```

The Dockerfile verifies unit syntax/dependencies with `systemd-analyze verify` and runs
the launcher as UID/GID 65534. Docker does not boot systemd as PID 1 in this test, so it
does not establish actual boot activation or systemd sandbox behavior. The container's
RAM, uptime, CPU and architecture belong to the Linux test environment, not a MikroTik
switch; model/revision must remain unavailable when the exact board is absent.

Run `python3 scripts/test_probe_linux.py` after building the test image to check local
readings, disconnected/online catalog behavior, unit validity and startup/SIGINT handling.
The unit checker alone gets a private `/tmp` RAM filesystem for temporary files. The
probe tests use an unprivileged UID, read-only root, no capabilities and no host mounts.
The reproducible base image is amd64; specify `--platform linux/amd64` when building on
an ARM64 host. This is CPU emulation for generic Linux software, not emulation of either
MikroTik board. See [the recorded validation](https://github.com/safin97/airlink-switch-manager/blob/main/firmware/integration/linux/validation.json)
for the actual run and its limits.

## Still required for the physical switches

- Exact-board source, configuration and image format, plus PCB/revision evidence.
- Safe switch/PoE/SFP, watchdog/sensor and flash drivers with bootloader preservation.
- A verified minimal root filesystem and init system; Python/CA storage and RAM budgets
  measured on the target, rather than assumed from this generic Linux test.
- Ordinary serial boot log and tested local console/recovery access before RAM boot.
- Separately authorized exact-board RAM boot, driver tests and reboot-to-RouterOS recovery.
- Agent transport to the dashboard, revision mapping, signed update trust and a tested
  installer/rollback design. Successful online discovery does not satisfy these items.

The [source-request draft](https://github.com/safin97/airlink-switch-manager/blob/main/firmware/crs112/vendor-source-request.txt)
remains unsent. See [the firmware workspaces](https://github.com/safin97/airlink-switch-manager/blob/main/firmware/README.md).
