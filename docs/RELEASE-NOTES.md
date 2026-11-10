# AirLink Switch Manager 1.0.0 — development prerelease

Flutter dashboard and backend for MikroTik CRS318-16P-2S+OUT and CRS112-8P-4S-IN,
with separate monitoring and explicitly confirmed PoE auto-on/off actions.

The fifth development prerelease adds a **generic Linux development integration overlay**
for the board probe, a systemd service, a staging tool and recorded isolated Linux tests.
`airlink-probe-linux-development.tar.gz` contains source/service files only, without a
kernel, Python runtime, root filesystem or boot image. **It is not switch firmware.**
Neither MikroTik board, RAM boot, flash layout, driver support nor recovery is verified.

It also includes **Board & online release check** in Updates,
an authenticated backend catalog endpoint and a read-only Linux probe with startup/
periodic reporting. The HTTPS firmware catalog is empty because no switch firmware is
verified. The probe is a prototype; it is not installed or tested on the switches.
No catalog response enables installation. See docs/BOARD-AGENT.md.

It also includes **Network** with DHCP/static IPv4 selection,
interface/prefix/gateway/DNS fields, address validation and local per-profile drafts.
Applying network settings to a device is not implemented. See docs/NETWORK.md.

It also includes **Updates** for future AirLink switch firmware:
reported board revision, local draft-manifest review, identity mismatch/staleness checks
and installation prerequisites. No firmware installation is implemented or enabled.
See firmware/UPDATE-PROTOCOL.md for the descriptor contract and remaining work.

## Included downloads

- `airlink-macos.zip`: optimized Intel/Apple Silicon macOS app; ad-hoc signed,
  not Developer-ID signed or notarized.
- `airlink-web-backend.zip`: compiled web client, Python backend, pinned dependencies
  and example configuration. Private credentials and verified SSH host keys must be
  configured on the backend. PoE controls are disabled until deliberately configured.
- `airlink-source.zip`: Flutter/platform sources, backend, tests, documentation and
  firmware research records. Local settings, credentials and generated caches excluded.
- `manifest.json` and `SHA256SUMS`: artifact sizes/hashes and verification scope.

## Software verification

Verified 2026-11-10: clean Flutter analysis, 27 passing Flutter tests, 72 passing
backend tests, and authentication against a real localhost backend with no routers.
Native demo integration/screenshots and macOS/web builds passed during development.
The Flutter client is unchanged from dev.4; the additional validation covers Linux
runtime and packaging. No host app rebuild was needed for this integration-only change.
macOS packaging checks signatures before and after archive extraction and verifies ZIP
integrity. These checks do not establish physical-device compatibility.

## Unfinished and excluded

No physical RouterOS monitoring or PoE action has been verified. Remote HTTPS hosting
has not been deployed. Native Windows/Linux/Android/iPhone binaries are not included.
This is a development prerelease, not production certification.

**No kernel, sysupgrade.bin, airlink.bin or other router firmware is included.** Exact
board support, switch/PoE drivers, flash layout, filesystem/image packaging and tested
RAM boot/recovery remain unfinished. Research sources are candidates, not validated
drivers for these boards. Do not upload the host-app archives as switch firmware.

See README.md for installation, backend configuration and the PoE approval flow;
docs/VALIDATION.md records test scope and remaining live acceptance work.
