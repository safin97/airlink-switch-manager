# Validation and delivery record

Date: **2026-11-10**, Europe/Zurich. Workspace inspection found an empty directory;
no previous app or collector was available to preserve.

## Verified software behavior

- Flutter/Dart formatting applied to app, unit/widget tests and integration driver.
- `flutter analyze`: **no issues found**.
- `flutter test`: **14 tests passed**. Covers both inventory layouts, phone/desktop
  responsiveness, all five sections, profiles without persisted tokens, remote HTTP
  rejection, incomplete response handling, no overlapping polls, stale-data retention,
  unsupported hardware and replies arriving after disconnect/demo switching. Added PoE
  confirmation/cancel flows at phone and desktop widths, demo isolation, separate-token
  requests, polling exclusion, stale readings after lost write replies and no automatic retry.
- Backend pytest: **52 tests passed**. Covers authentication, HTTPS enforcement and
  spoofed forwarded headers, safe profile responses, rejection of writes to monitoring endpoints, strict SSH
  host-key policy selection, escaped/Unicode framing, truncated/malformed responses,
  units, lossless counters, rate deltas, reset/reboot/missing samples, model/architecture
  and physical-port validation, partial responses, locks, backoff and reconnection.
  PoE tests cover both models, auto-on/off, denied monitoring tokens, port allowlists,
  explicit confirmation, expiration/replay, changed serial/port/mode, command injection,
  missing identity, unsupported modes, write/readback failure, shared locks and error redaction.
- Python source compilation passed with its cache directed into a temporary directory.
- Real uvicorn process smoke test passed: missing credentials returned 401 and a valid
  random temporary token returned safe profile JSON. Configuration contained **zero
  routers**, so this test did not contact any device.
- Native macOS Flutter integration walkthrough passed: connection screen, both demos,
  all dashboard sections, disconnect/reconnect and phone-width layout rendering.
  The PoE update adds a native demo confirmation and simulated Off action, with actual
  [control](screenshots/demo-poe-controls-macos.png) and
  [confirmation](screenshots/demo-poe-confirmation-macos.png) screenshots.
- Native macOS debug app was built and launched. Optional Flutter web release build
  also passed. Output locations: `build/macos/Build/Products/Debug/AirLink.app` and
  `build/web/` (build products are intentionally gitignored).
- Optimized macOS release build also completed (universal arm64/x86_64). The new
  `scripts/package_release.py` creates host-app and web/backend development archives.
  Staging omits Finder/resource-fork metadata introduced by Desktop file-provider
  storage; deep/strict signature verification passes before and after ZIP extraction.
  The signature is ad-hoc, not Developer ID, and the app is not notarized. ZIP CRC and
  SHA-256 checks accompany the artifacts. No router firmware is included or uploaded.

## Actual application screenshots

PNG files under [screenshots/](screenshots/) are captures of the running native Flutter
application's render surface via `RenderRepaintBoundary.toImage`, exported by the Flutter
integration driver. The desktop surface is 1440×1180 logical pixels; the phone-width
surface is 390×844. Raster capture scale is 1.5. The phone-width image is a responsive
layout test on macOS, **not a screenshot from an iPhone or Android device**.

The native OS screen-capture service failed, so these images exclude macOS window chrome.
The Flutter driver reported an `integration_test plugin was not detected` warning on
macOS, but its VM-service test result and explicit screenshot response callback completed
successfully. The files and [capture metadata](screenshots/capture.json) were inspected.

All telemetry screenshots are labeled **DEMO MODE**. They contain simulated values,
not readings from either physical switch. No image-generation tool or mockup was used.

## What has not been verified

- **Live RouterOS devices:** no management address, credentials or independently verified
  SSH host key was supplied. Neither physical model or RouterOS version was exercised.
  SSH scripts are based on authoritative RouterOS documentation and synthetic fixtures;
  fixture tests do not execute the RouterOS interpreter or establish hardware compatibility.
- **Optional sensors/fields:** exact `as-value` numeric representations and command support
  still need real captures. Unknown units/unsupported commands become unavailable. There
  is no fabricated fallback and no assumption that REST exists.
- **Platforms:** Windows/Linux platform files are generated but builds need their host
  toolchains. Android/iPhone files are generated; their builds and real-device behavior
  were not tested. Android doctor reported unaccepted SDK licenses. No license was accepted
  or personal iPhone signing configuration changed as part of this task.
- **Remote deployment:** the HTTPS/authentication configuration is implemented and tested
  in-process, but no public hostname, certificate, reverse proxy or service was deployed.
- **PoE control:** implemented and exercised with synthetic SSH/HTTP fixtures and local
  demo interactions only. No physical power change or RouterOS interpreter execution
  was tested. Existing forced-on ports in the user's evidence were not changed.
- **Operations:** separate monitoring/operator privileges exist, but no named multi-user
  accounts, per-user device scopes, durable action audit trail, persistent time
  series, background polling without a client, multi-worker synchronization, packaging
  installer, signed/notarized desktop distribution or production security audit.
- **Firmware:** no exact-board target, DTS, flash layout, switch/PoE driver, root filesystem
  image, RAM-boot test, persistent installation or verified recovery. See the separate
  [firmware evidence checklist](../firmware/README.md).

## Exact live acceptance procedure when access is provided

1. Privately configure each exact product, backend-only read/SSH account and a separately
   verified host key. Confirm the installed RouterOS release and operating mode; SwOS
   monitoring is not implemented. Do not relax host-key verification or grant write rights.
2. Run a manual snapshot and compare model, architecture, reported/default port names and
   counts with the device. Stop if identity or inventory differs. Keep a redacted fixture
   for each version; include a renamed port and missing optional sensor if possible.
3. Compare RX/TX counters with RouterOS, then observe at least two timed samples. Check
   calculated Mbps, idle link behavior and units. Validate counter-reset behavior with
   controlled fixtures before any separately authorized physical reboot/reset experiment.
4. Compare enabled state, link speed/duplex and actual available PoE voltage/current/power,
   CPU/memory/uptime/version/temperature. Confirm that unsupported values remain unavailable.
5. Interrupt only the test client's network path to simulate a disconnect. Verify timestamps
   stop advancing, stale/error warnings appear, reconnect/backoff works and rate history
   shows a gap. Do not disrupt the switch's production management connection.
6. Test a wrong API token, unknown/mismatched SSH host key, missing command permission,
   unsupported model fixture and parallel clients. Confirm no router settings are changed.
7. Verify trusted HTTPS from each intended client platform and review backend service
   permissions, token rotation procedure, access scope and logging before deployment.

For optional PoE acceptance, use a deliberately selected non-management test port and
load with recovery access. Configure the separate control account/token and explicit
port allowlist per README. Verify preparation/cancellation changes nothing; then obtain
explicit confirmation for each Off/On (Auto) operation and compare RouterOS mode and
actual power readings. Check loss-of-response handling using a test proxy/client path,
not by powering down production management infrastructure. Never substitute forced-on
or assume auto-on will power every load. This hardware acceptance remains outstanding.

This project is a validated software development baseline, **not a production-readiness,
live-device-verification or installable-firmware claim**.
