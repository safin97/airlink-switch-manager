"""Offline signed-artifact verification. No download, install, reboot or flash API."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import stat

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey

from .updates import PRODUCTS, timestamp, version

DOMAIN = b'AirLink firmware manifest v1\x00'
MANIFEST_LIMIT = 16384


class VerificationError(ValueError):
    pass


def _regular_file(path):
    flags = os.O_RDONLY | getattr(os, 'O_NONBLOCK', 0) | getattr(os, 'O_NOFOLLOW', 0)
    if Path(path).is_symlink():
        raise VerificationError('symlink_input_rejected')
    fd = os.open(path, flags)
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            raise VerificationError('regular_file_required')
        return os.fdopen(fd, 'rb')
    except Exception:
        os.close(fd)
        raise


def _read_small(path, limit):
    with _regular_file(path) as stream:
        if os.fstat(stream.fileno()).st_size > limit:
            raise VerificationError('input_too_large')
        raw = stream.read(limit + 1)
        if len(raw) > limit:
            raise VerificationError('input_too_large')
        return raw


def _parse(raw):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise VerificationError('duplicate_manifest_key')
            result[key] = value
        return result
    try:
        manifest = json.loads(raw.decode('utf-8'), object_pairs_hook=unique)
    except (ValueError, UnicodeError, RecursionError):
        raise VerificationError('invalid_manifest_json') from None
    keys = {'schema', 'product', 'architecture', 'board_revision', 'version',
            'sha256', 'size_bytes', 'issued_at', 'expires_at'}
    if not isinstance(manifest, dict) or set(manifest) != keys:
        raise VerificationError('invalid_manifest_fields')
    if (not all(isinstance(manifest[k], str) for k in keys - {'size_bytes'})
            or manifest['schema'] != 'airlink.firmware-signed.v1'
            or PRODUCTS.get(manifest['product']) != manifest['architecture']
            or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.+-]{0,63}', manifest['board_revision'])
            or not re.fullmatch(r'[a-f0-9]{64}', manifest['sha256'])
            or type(manifest['size_bytes']) is not int or not 0 < manifest['size_bytes'] < 2**32):
        raise VerificationError('invalid_manifest_values')
    return manifest


def verify_artifact(manifest_path, signature_path, image_path, trusted_key_path, *,
                    model, architecture, board_revision, current_version, max_image_bytes,
                    clock=None):
    """Verify bytes and operator-supplied target claims; never certify hardware.

    The trusted public key and current-version/size policy must be supplied outside
    the artifact. A future installer must obtain these from trusted device state.
    """
    raw = _read_small(manifest_path, MANIFEST_LIMIT)
    signature = _read_small(signature_path, 64)
    public_key = _read_small(trusted_key_path, 32)
    if len(signature) != 64 or len(public_key) != 32:
        raise VerificationError('invalid_signature_or_key_length')
    try:
        Ed25519PublicKey.from_public_bytes(public_key).verify(signature, DOMAIN + raw)
    except (InvalidSignature, ValueError):
        raise VerificationError('signature_verification_failed') from None
    manifest = _parse(raw)
    if (manifest['product'] != model or manifest['architecture'] != architecture or
            manifest['board_revision'] != board_revision):
        raise VerificationError('target_claims_mismatch')
    try:
        if version(manifest['version']) <= version(current_version):
            raise VerificationError('same_or_older_version_rejected')
        issued, expires = timestamp(manifest['issued_at']), timestamp(manifest['expires_at'])
        current = clock or datetime.now(timezone.utc)
        if (current.tzinfo is None or (issued - current).total_seconds() > 300 or
                expires <= current or not 0 < (expires - issued).total_seconds() <= 30 * 86400):
            raise VerificationError('manifest_time_policy_failed')
    except VerificationError:
        raise
    except (ValueError, TypeError):
        raise VerificationError('version_or_time_policy_failed') from None
    if (type(max_image_bytes) is not int or not 0 < max_image_bytes < 2**32 or
            manifest['size_bytes'] > max_image_bytes):
        raise VerificationError('image_exceeds_operator_size_policy')
    with _regular_file(image_path) as stream:
        before = os.fstat(stream.fileno())
        if before.st_size != manifest['size_bytes']:
            raise VerificationError('image_size_mismatch')
        digest = hashlib.sha256()
        size = 0
        while True:
            chunk = stream.read(min(65536, manifest['size_bytes'] + 1 - size))
            if not chunk:
                break
            size += len(chunk)
            if size > manifest['size_bytes']:
                raise VerificationError('image_changed_during_verification')
            digest.update(chunk)
        after = os.fstat(stream.fileno())
        fingerprint = lambda s: (s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_ctime_ns)
        if fingerprint(before) != fingerprint(after):
            raise VerificationError('image_changed_during_verification')
        if size != manifest['size_bytes'] or digest.hexdigest() != manifest['sha256']:
            raise VerificationError('image_digest_mismatch')
    return {'schema_version': 1, 'checked_at': datetime.now(timezone.utc).isoformat(),
            'status': 'signature_and_bytes_verified_only',
            'public_key_sha256': hashlib.sha256(public_key).hexdigest(),
            'manifest_sha256': hashlib.sha256(raw).hexdigest(),
            'artifact_sha256': digest.hexdigest(), 'artifact_size_bytes': size,
            'version': manifest['version'], 'target_claims_match': True,
            'signature_verified': True, 'artifact_integrity_verified': True,
            'board_identity_source': 'operator_supplied_not_hardware_verified',
            'image_format_verified': False, 'hardware_verified': False,
            'installation_allowed': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['manifest', 'signature', 'image', 'trusted-key']:
        parser.add_argument('--' + name, type=Path, required=True)
    for name in ['model', 'architecture', 'board-revision', 'current-version']:
        parser.add_argument('--' + name, required=True)
    parser.add_argument('--max-image-bytes', type=int, required=True)
    args = parser.parse_args()
    try:
        result = verify_artifact(args.manifest, args.signature, args.image, args.trusted_key,
                                 model=args.model, architecture=args.architecture,
                                 board_revision=args.board_revision, current_version=args.current_version,
                                 max_image_bytes=args.max_image_bytes)
    except (OSError, ValueError):
        # Do not echo untrusted payloads, paths or key contents into logs.
        print(json.dumps({'status': 'verification_failed', 'installation_allowed': False}))
        raise SystemExit(1) from None
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
