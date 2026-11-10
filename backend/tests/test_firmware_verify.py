from datetime import datetime, timedelta, timezone
import hashlib
import json
import os
import subprocess
import sys

import pytest
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

from airlink.firmware_verify import DOMAIN, VerificationError, verify_artifact

NOW = datetime(2026, 11, 10, 12, tzinfo=timezone.utc)


@pytest.fixture
def artifact(tmp_path):
    # Synthetic test bytes only. No kernel, flash image or persistent signing key.
    image = tmp_path / 'synthetic-payload.dat'
    image.write_bytes(b'NOT A FIRMWARE IMAGE\n')
    key = Ed25519PrivateKey.generate()
    public = tmp_path / 'test-only.pub'
    public.write_bytes(key.public_key().public_bytes_raw())
    manifest_path, signature_path = tmp_path / 'manifest.json', tmp_path / 'manifest.sig'
    manifest = {'schema': 'airlink.firmware-signed.v1', 'product': 'CRS112-8P-4S-IN',
                'architecture': 'mipsbe', 'board_revision': 'r2', 'version': '1.1.0',
                'sha256': hashlib.sha256(image.read_bytes()).hexdigest(),
                'size_bytes': image.stat().st_size, 'issued_at': NOW.isoformat(),
                'expires_at': (NOW + timedelta(days=1)).isoformat()}
    def sign(changes=None, raw=None):
        data = json.dumps(dict(manifest, **(changes or {})), sort_keys=True).encode() if raw is None else raw
        manifest_path.write_bytes(data)
        signature_path.write_bytes(key.sign(DOMAIN + data))
    sign()
    def verify(**changes):
        options = {'model': 'CRS112-8P-4S-IN', 'architecture': 'mipsbe',
                   'board_revision': 'r2', 'current_version': '1.0.0',
                   'max_image_bytes': 1024, 'clock': NOW}
        options.update(changes)
        return verify_artifact(manifest_path, signature_path, image, public, **options)
    return {'image': image, 'key': key, 'public': public, 'manifest': manifest_path,
            'signature': signature_path, 'sign': sign, 'verify': verify}


def test_verified_bytes_never_authorize_hardware_installation(artifact):
    result = artifact['verify']()
    assert result['signature_verified'] and result['artifact_integrity_verified']
    assert result['target_claims_match']
    assert result['installation_allowed'] is False and result['hardware_verified'] is False
    assert result['image_format_verified'] is False


@pytest.mark.parametrize('mutation', ['payload', 'signature', 'public_key', 'manifest'])
def test_tampering_and_wrong_key_rejected(artifact, mutation):
    if mutation == 'payload':
        original = artifact['image'].read_bytes()
        artifact['image'].write_bytes(b'X' + original[1:])
    elif mutation == 'signature':
        artifact['signature'].write_bytes(b'\0' * 64)
    elif mutation == 'public_key':
        artifact['public'].write_bytes(Ed25519PrivateKey.generate().public_key().public_bytes_raw())
    else:
        artifact['manifest'].write_bytes(artifact['manifest'].read_bytes() + b' ')
    with pytest.raises(VerificationError): artifact['verify']()


@pytest.mark.parametrize('changes', [
    {'board_revision': 'r4'}, {'architecture': 'arm'}, {'version': '1.0.0'},
    {'version': '0.9.0'}, {'version': 'unknown'}, {'size_bytes': True},
    {'installation_allowed': True}, {'issued_at': (NOW + timedelta(days=1)).isoformat()},
    {'expires_at': (NOW - timedelta(seconds=1)).isoformat()},
    {'expires_at': (NOW + timedelta(days=31)).isoformat()},
    {'issued_at': '2026-11-10T12:00:00'},
])
def test_valid_signature_does_not_bypass_target_schema_version_or_time_policy(artifact, changes):
    artifact['sign'](changes)
    with pytest.raises(VerificationError): artifact['verify']()


def test_unknown_current_version_capacity_and_duplicate_fields_rejected(artifact):
    for changes in [{'current_version': None}, {'max_image_bytes': 1}, {'max_image_bytes': True}]:
        with pytest.raises(VerificationError): artifact['verify'](**changes)
    raw = artifact['manifest'].read_bytes().replace(b'{', b'{"version":"1.2.0",', 1)
    artifact['sign'](raw=raw)
    with pytest.raises(VerificationError): artifact['verify']()


def test_wrong_size_oversized_metadata_and_symlinks_rejected(artifact, tmp_path):
    artifact['image'].write_bytes(b'short')
    with pytest.raises(VerificationError): artifact['verify']()
    artifact['manifest'].write_bytes(b'x' * 16385)
    with pytest.raises(VerificationError): artifact['verify']()
    artifact['sign']()
    image = artifact['image']
    target = tmp_path / 'target.dat'
    image.rename(target)
    image.symlink_to(target)
    with pytest.raises(VerificationError): artifact['verify']()


@pytest.mark.skipif(not hasattr(os, 'mkfifo'), reason='POSIX FIFO test')
def test_fifo_is_rejected_without_blocking(artifact):
    artifact['image'].unlink()
    os.mkfifo(artifact['image'])
    with pytest.raises(VerificationError): artifact['verify']()


def test_cli_failure_never_echoes_payload_or_keys(artifact):
    artifact['signature'].write_bytes(b'not-a-real-signature')
    command = [sys.executable, '-m', 'airlink.firmware_verify',
               '--manifest', str(artifact['manifest']), '--signature', str(artifact['signature']),
               '--image', str(artifact['image']), '--trusted-key', str(artifact['public']),
               '--model', 'CRS112-8P-4S-IN', '--architecture', 'mipsbe', '--board-revision', 'r2',
               '--current-version', '1.0.0', '--max-image-bytes', '1024']
    result = subprocess.run(command, capture_output=True, text=True, timeout=10)
    assert result.returncode == 1 and not result.stderr
    assert json.loads(result.stdout) == {'status': 'verification_failed', 'installation_allowed': False}
