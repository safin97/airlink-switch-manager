"""Synthetic archives only: no vendor binary fixtures or package execution."""
import importlib.util
from pathlib import Path
import struct
import zlib

import pytest

SPEC = importlib.util.spec_from_file_location(
    'npk_inspector', Path(__file__).resolve().parents[2] / 'scripts/inspect_npk.py')
npk = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(npk)


def package(payload=b'', kind=22):
    part = struct.pack('<HI', kind, len(payload)) + payload
    return npk.MAGIC + struct.pack('<I', len(part)) + part


def object_stream(name=b'boot/kernel', body=b'test'):
    return (struct.pack('<H', 0o100644) + bytes(22)
            + struct.pack('<IH', len(body), len(name)) + name + body)


def test_valid_package_and_reference_hash():
    data = package(zlib.compress(object_stream()), 4)
    report = npk.inspect(data)
    assert report['sha256'] == npk.digest(data)['sha256']
    assert report['files'][0]['name'] == 'boot/kernel'
    assert report['files'][0]['size_bytes'] == 4
    assert report['installable_airlink_firmware'] is False
    assert report['vendor_signature_verified'] is False


@pytest.mark.parametrize('data', [b'', b'not an npk', package()[:-1],
                                  package() + b'trailing',
                                  npk.MAGIC + struct.pack('<I', 1) + b'x',
                                  npk.MAGIC + struct.pack('<I', 6)
                                  + struct.pack('<HI', 4, 100)])
def test_rejects_invalid_container(data):
    with pytest.raises(ValueError):
        npk.inspect(data)


@pytest.mark.parametrize('payload', [b'not zlib', zlib.compress(b'bad'),
                                     zlib.compress(object_stream())[:-1],
                                     zlib.compress(object_stream()) + b'trailing',
                                     zlib.compress(object_stream()[:-1])])
def test_rejects_invalid_object_stream(payload):
    with pytest.raises(ValueError):
        npk.inspect(package(payload, 4))


def test_decompression_bound(monkeypatch):
    monkeypatch.setattr(npk, 'MAX_BYTES', 256)
    with pytest.raises(ValueError, match='oversized'):
        list(npk.objects(zlib.compress(bytes(257))))


def test_archive_names_are_metadata_only(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    report = npk.inspect(package(zlib.compress(object_stream(b'../escape')), 4))
    assert report['files'][0]['name'] == '../escape'
    assert list(tmp_path.iterdir()) == []


def test_kernel_xz_is_inspected_without_execution():
    import lzma
    raw = b'Linux version TEST\0ccs112r4\0spi-poe-pse\0'
    result = npk.inspect_kernel(b'prefix' + lzma.compress(raw))
    stream = result['embedded_xz_streams'][0]
    assert stream['offset'] == 6
    assert stream['linux_version_string'] == 'Linux version TEST'
    assert 'ccs112r4' in stream['candidate_strings']
    assert result['boot_compatibility_verified'] is False


def test_part_count_limit(monkeypatch):
    monkeypatch.setattr(npk, 'MAX_RECORDS', 0)
    with pytest.raises(ValueError, match='count'):
        npk.inspect(package())
