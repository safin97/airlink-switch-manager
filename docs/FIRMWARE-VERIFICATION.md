# Offline firmware artifact verification — development component

`airlink.firmware_verify` is an offline backend/workstation tool for checking a signed
artifact before any future installation work. It performs **no download, installation,
flash write, reboot, PoE change or device connection**. It cannot create a working
initial image from the Flutter application. No real switch image or production signing
key is supplied, generated or published by this change.

## What is checked

- Ed25519 signature against a separately supplied trusted public key.
- Bounded, strict UTF-8 JSON schema, without duplicate or unexpected fields.
- Exact product, architecture and board-revision claims supplied by the operator.
- A strictly newer numeric `major.minor.patch` version than the supplied baseline.
- Timezone-aware issuance/expiry, maximum 30-day validity, and no issuance more than
  five minutes ahead of the clock. An expired manifest fails verification.
- A positive size within the operator-supplied limit, exact file length and SHA-256.
- Regular input files only, without symlinks or FIFO/device reads. Hashing is streamed;
  detected changes to the open file during verification fail the check.

The reported target identity and current version are **operator inputs**, not independent
hardware evidence. The size limit is an operator policy, not a discovered flash map.
A valid signature proves the bytes match the holder of the supplied public key; it does
not establish that this key is an authorized publisher unless the operator has already
verified/provisioned it through a trusted process.

## Format

The manifest has exactly these fields:

| Field | Meaning |
|---|---|
| `schema` | `airlink.firmware-signed.v1` |
| `product` | Exact supported product code |
| `architecture` | `mipsbe` for CRS112, `arm` for netPower 16P |
| `board_revision` | Explicit board revision; no wildcard |
| `version` | Stable numeric `major.minor.patch` |
| `sha256` | Lowercase SHA-256 hex digest of the artifact bytes |
| `size_bytes` | Positive integer, less than 4 GiB; not a flash-capacity claim |
| `issued_at`, `expires_at` | ISO-8601 timestamps with timezones |

The detached signature is 64 raw bytes. The public key is 32 raw Ed25519 bytes. The
signed message is the exact concatenation of `b'AirLink firmware manifest v1\x00'` and
the original manifest bytes. Whitespace changes invalidate the signature. A key must
never be trusted merely because it arrived with the image. No private signing key belongs
on a switch, in Flutter, in logs, or in this repository.

This development format is separate from the UI's draft metadata descriptor and the
unsigned online discovery catalog. The online catalog remains unsigned and empty; its
`signature_verified` and `installation_allowed` values remain false.

## Use after obtaining a real artifact and independently trusted key

The backend environment includes the explicitly pinned `cryptography==50.0.2` dependency.
The following uses placeholder paths and requires a justified size policy; it is not a
command to install firmware:

```sh
PYTHONPATH=backend backend/.venv/bin/python -m airlink.firmware_verify \
  --manifest /path/to/reviewed-manifest.json \
  --signature /path/to/reviewed-manifest.sig \
  --image /path/to/reviewed-artifact \
  --trusted-key /path/to/independently-trusted-ed25519.pub \
  --model CRS112-8P-4S-IN --architecture mipsbe --board-revision r2 \
  --current-version CURRENT_AIRLINK_VERSION --max-image-bytes REVIEWED_SIZE_LIMIT
```

The placeholders intentionally are not guessed values. Unknown current version fails
verification. A first installation needs a separate verified provisioning workflow;
this tool does not bypass that by accepting an assumed version.

Success reports `signature_and_bytes_verified_only`, public-key/manifest/artifact
fingerprints and integrity results. It always reports `installation_allowed=false`,
`hardware_verified=false` and `image_format_verified=false`. Failure returns a generic
JSON failure with exit code 1, without echoing file contents, paths or key material.

## Remaining integration

An actual updater still needs board-verified boot/network/recovery support, artifact
format inspection, device-owned identity and version state, publisher-key provisioning
and rotation/revocation, rollback-resistant state, a signed release feed, authenticated
permissions, explicit operator confirmation and a tested flash/rollback transaction.
Verification is a point-in-time report; a future installer must verify and use the same
immutable bytes at the moment of installation, not trust a past JSON result.

The minimal Linux probe overlay intentionally excludes this verifier and its additional
crypto runtime. On-device storage/RAM suitability and integration are not verified.
Tests generate temporary synthetic payloads and in-memory test keys only; they do not
produce or validate a MikroTik firmware image.

Cryptographic primitive reference: [cryptography Ed25519 documentation](https://cryptography.io/en/latest/hazmat/primitives/asymmetric/ed25519/).
