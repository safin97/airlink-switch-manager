# Monitoring and optional PoE API contract (snapshot schema version 1)

Backend JSON uses UTC ISO-8601 timestamps. Units are explicit both in field names and
in the top-level `units` map. Unknown/unavailable readings are JSON `null`; no sensor
or link speed is inferred from the product's advertised capability.

| Field | Meaning |
|---|---|
| `mode` | Always `live` from backend; demo exists only inside Flutter |
| `device_id` | Configured backend profile ID |
| `status` | `connected`, `partial`, `disconnected`, or `refreshing` |
| `stale` | Cached readings after a failure or while a concurrent refresh runs |
| `last_success_at` | Last completed collection; does not move on failures |
| `collected_at` | Completion time of original collection |
| `served_at` | Time a stale response was served, when present |
| `device` | Canonical product code, reported model, identity, architecture, verified flag |
| `system` | CPU percent, free/total memory bytes, textual RouterOS uptime/version, available named temperatures |
| `system.observed_at` / `health_at` | Time system/health responses were received |
| `ports` | Verified physical interface inventory, in physical order |
| `warnings` | Section and sanitized failure codes, without raw SSH output |

Each port contains:

- `id`, `name`, `default_name`, `kind` (`Ethernet`, `SFP`, `SFP+`). IDs and factory names
  are validated; renamed interfaces are not confused with physical slot numbers.
- `enabled`: boolean or null; `link`: reported status or null; `speed_mbps` and
  `full_duplex`: negotiated readings only, not configured maximums.
- `rx_bytes`, `tx_bytes`: **decimal strings** or null, preserving unsigned counter
  precision across Dart native and JavaScript/web clients. Do not parse through float.
- `rx_mbps`, `tx_mbps`: numbers or null. Calculated in the backend from integer counter
  differences × 8 / monotonic elapsed seconds / 1,000,000.
- `counter_reset`: a counter decrease or detected reboot reset the rate baseline.
  First sample, missing previous counters, elapsed time ≤ 0 and reset intervals have
  null rates. A router restart with lower uptime resets all port baselines.
- `observed_at`, `counters_at`: separate link/counter collection times or null.
- `poe`: `status`, `configuration_mode`, `voltage_v`, `current_a`, `power_w`, `observed_at`. Fiber ports have
  null PoE readings. Values are not inferred from electrical formulas.

A collection is sequential and **not atomic** across all sensors. Section/port timestamps
matter. On an optional-command failure, current unavailable fields become null and the
section is listed in warnings; old per-field values are not silently reused. On a complete
collection failure, the previous snapshot is clearly stale. A model mismatch discards
cached readings to avoid showing data from a different switch.

## Transport and parsing

SSH uses Paramiko `RejectPolicy` and only the explicitly configured known-host file;
agent and implicit key discovery are disabled. Each poll opens a fresh verified session,
closes it afterward, and has connect/auth/banner timeouts plus a 45-second command budget.
Commands have six-second limits and bounded output. A failed request backs off up to
30 seconds. Successful snapshots are cached for two seconds to prevent rapid duplicate
polls. Only one poll per device runs at a time, across all clients in the one-worker process.

The collector uses RouterOS `print as-value` and `monitor once as-value`, with a small
read-only local script that emits `ALBEGIN`, framed records, and a mandatory `ALDONE`.
Every scalar field is independently framed; `%`, tab, CR and LF are escaped. Array-valued
properties such as advertised link modes are skipped. Lists of records are detected by
an array at numeric index zero, not merely by the presence of any array-valued property.
This avoids CLI column widths, row flags, semicolon splitting and line wrapping.
An incomplete or malformed frame, duplicate field or RouterOS error text is rejected.
No remote script is saved and no persistent global variables are created.

Only validated internal interface IDs are inserted into link commands. PoE monitoring
resolves the current interface name inside RouterOS from the validated ID. Arbitrary
user names cannot inject script text. The collector's commands remain monitoring-only;
explicit writes live in the separate PoE control service.

Authoritative command references:

- [RouterOS scripting and as-value](https://manual.mikrotik.com/docs/developer-guides/scripting/scripting-tips-and-tricks/)
- [Ethernet monitoring](https://help.mikrotik.com/docs/spaces/ROS/pages/8323191/Ethernet)
- [PoE monitoring and units](https://help.mikrotik.com/docs/spaces/ROS/pages/19136769/PoE-Out)
- [SSH command/error behavior](https://manual.mikrotik.com/docs/management-tools/ssh/)

The documented bare PoE current is milliamps, normalized to amperes; explicit mA/A
suffixes are respected. Explicit voltage/power suffixes are converted to V/W. Bare voltage/power without a unit suffix is left unavailable pending verified
RouterOS captures, rather than assuming a scale. No SNMP scaling is applied to SSH values. Captures from actual installed RouterOS versions are
still required to verify their exact `as-value` representations and sensor availability.

## Optional PoE control endpoints

Snapshots add `controls.poe_ports`, the configured factory-port allowlist, and
`controls.operator_token_required: true`. The monitoring token cannot authorize writes.
All control calls use `Authorization: Bearer <AIRLINK_CONTROL_TOKEN>` over HTTPS
(the existing loopback development exception applies). No secrets belong in JSON or URLs.

`POST /api/v1/devices/{id}/poe/prepare` accepts:

```json
{"default_name":"ether2","expected_name":"camera","mode":"off"}
```

Only `off` and `auto-on` are allowed. Preparation performs read-only checks through
the separate operator SSH account. It returns `confirmation_id`, `expires_in_seconds`
(60), `device_id`, `device_label`, `port`, `name`, `previous_mode`, `requested_mode`,
`prepared_at` and a management-disconnection warning. No power is changed yet.

`POST /api/v1/devices/{id}/poe/commit` accepts the returned confirmation ID plus
`confirmed: true` (a strict JSON boolean). No arbitrary commands or port overrides are
accepted. It consumes the confirmation before connecting, verifies the board serial,
model/revision, physical port ID/default/current name and previous mode against the
prepared state, and performs the requested mode change once. Serial values are not
returned. It checks the factory name and previous mode again at the write site.
RouterOS configuration changes by external administrators are not transactionally locked;
coordinate concurrent administration during control actions.

Successful response: `status: configuration_verified`, `device_id`, `port`,
`configuration_mode`, `verified_at`, `power_delivery_verified: false`.
This confirms readback of configuration only; obtain electrical readings from monitoring.

Errors: 403 permission/allowlist, 409 busy/changed/expired/used confirmation, 422 invalid
input/unsupported identity or configuration, 503 preflight failed before a write,
502 outcome unknown after dispatch. Never automatically retry a commit, including on
timeouts or HTTP errors. The cache becomes stale on commit attempts. Shared per-device
locks prevent local poll/control overlap; one worker is required. A new prepare replaces
the device's previous confirmation. Pending confirmations are memory-only.

## Scope and limits

History is client-session memory only. Device profiles and API access are managed by a
single backend administrator. Monitoring and operator tokens have separate privileges;
the operator token covers all configured control allowlists. There are no named user
accounts, per-user device scopes, durable control audit log, key rotation UI, persistent
history database or background daemon polling. Interface enable/disable and forced-on
PoE endpoints are not provided. Live power-control behavior remains unverified.

The UI rejects remote HTTP, credential-bearing URLs, query-string tokens and invalid
schemas. HTTPS uses platform certificate verification. Failed/aged readings are marked
stale, with the last successful time visible. Age threshold is max(15 seconds,
3 × configured interval); manual mode therefore becomes stale after 15 seconds.

## Firmware update metadata

Snapshot `device.board_revision` is the optional RouterOS-reported revision, or null.
It is not inferred from the profile, model alias or saved research evidence. The Flutter
Updates section reviews draft manifest metadata locally; it has no update/write API.
See [the firmware update contract](../firmware/UPDATE-PROTOCOL.md). Installation remains
unavailable for both models.
