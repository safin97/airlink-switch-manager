# Future AirLink firmware updates

The dashboard **Updates** section targets AirLink firmware on the switch. It does not
update RouterOS, RouterBOOT, the desktop app or the backend. Neither switch currently
has a verified AirLink image or a device-side updater. Installation is always disabled,
including in demo mode. There is no upload, flash, reboot or update-install API.

The **Board & online release check** card now provides authenticated, read-only catalog
discovery using current RouterOS identity. A Linux probe supports startup/periodic reports
as a prototype for future images. See [the implementation and limits](../docs/BOARD-AGENT.md).
The draft descriptor below remains separate from the unsigned online discovery catalog.

## Using the implemented section

1. Connect to a backend device, or use the clearly labeled demo.
2. Open **Updates**. Check model, architecture, reported board revision and last snapshot
   time. Revision comes from the current SSH routerboard response, not the saved model
   selection or a historical user report. Missing revisions remain unavailable.
3. Paste a draft descriptor and choose **Review metadata**. Processing is local;
   no network request or device action occurs. Editing the text clears its review.
4. Read mismatches, unavailable identity fields and stale/demo warnings. Identity checks
   are re-evaluated against current snapshots. The declared digest and size are displayed
   as declarations; no image bytes or signatures are verified.

A matching descriptor is **not approval to install**. The dashboard is not a security
boundary for future installation; all checks must eventually be enforced by a trusted
backend and device-side agent as well. An old client or modified UI must not bypass them.

## Draft descriptor contract

This is a development-only metadata format, not an OpenWrt image format, release
manifest, trusted signing envelope or compatibility guarantee. Exactly these fields
are accepted, within 16 KiB of UTF-8 JSON:

```json
{
  "schema": "airlink.firmware-manifest.draft1",
  "product": "CRS112-8P-4S-IN",
  "architecture": "mipsbe",
  "board_revision": "r2",
  "version": "0.0.0-example-not-installable",
  "image_type": "sysupgrade",
  "sha256": "0000000000000000000000000000000000000000000000000000000000000000",
  "size_bytes": 1
}
```

The digest and size above are **placeholders, not a real artifact**. `sysupgrade` is only
the draft type label; it does not establish that either board supports sysupgrade.
Products are exactly `CRS112-8P-4S-IN` / `mipsbe` or `CRS318-16P-2S+OUT` / `arm`.
Revision and version must be explicit 1–64 character alphanumeric strings (also allowing
`.`, `+`, `_`, `-` after the first character); wildcards are rejected. No netPower revision
is presumed. Size is a positive integer up to 4 GiB minus one byte, a parser bound **not
the board flash capacity**. Digest is 64 hexadecimal characters. Extra fields, including
claims such as `signature_verified`, are rejected rather than trusted.

## Work required for a real installed-device updater

All of the following remain unfinished:

- Exact-board support, verified device tree/SoC support, flash layout and bootloader
  preservation; tested Ethernet/switch ASIC/SFP/offload and safe PoE drivers.
- Root filesystem, board-specific image packaging, watchdog and temperature support.
- Verified RAM boot and recovery with local serial/physical access. Remote-only access
  is insufficient for first-board bring-up or recovery testing.
- A defined signed image/manifest format, pinned publisher trust keys, key rotation,
  full image digest/size verification, trusted release metadata and downgrade policy.
- An authenticated HTTPS device-side agent reporting actual firmware version, exact
  board identity, update capabilities and operation status. No arbitrary shell API.
- An explicit operator-only prepare/confirm transaction, single-use expiry, fresh
  identity/image checks and a lock excluding overlapping polling, PoE and update writes.
- Tested backup/configuration migration, bootloader preservation, power-loss behavior,
  post-boot health confirmation and a recovery/rollback strategy supported by the actual
  storage layout. Do not assume dual-image slots fit this hardware.
- Visible maintenance/downtime warnings, including potential management/PoE/forwarding
  loss; confirmation immediately before a write; reconnect and uncertain-outcome handling
  with no automatic retry of a flash operation.

Implementation of those components depends on verified board evidence and hardware
testing. No device settings or firmware were changed by adding this section.
