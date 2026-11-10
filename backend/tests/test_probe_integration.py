import hashlib
import importlib.util
import json
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('stage_probe', ROOT / 'scripts/stage_board_probe.py')
stage_probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(stage_probe)


def test_overlay_has_only_runtime_files_and_hashes(tmp_path):
    dest = tmp_path / 'rootfs'
    manifest = stage_probe.stage(dest)
    assert manifest['installable_switch_firmware'] is False
    assert manifest['target_board'] is None and manifest['service_enabled'] is False
    assert len(manifest['files']) == 6
    for name, metadata in manifest['files'].items():
        path = dest / name
        assert hashlib.sha256(path.read_bytes()).hexdigest() == metadata['sha256']
        assert path.stat().st_size == metadata['bytes']
        assert path.stat().st_mode & 0o777 == 0o644
    assert json.loads((dest / 'integration-manifest.json').read_text()) == manifest
    assert {p.name for p in dest.rglob('*.py')} == {'__init__.py', 'board_probe.py', 'updates.py', 'launcher.py'}
    assert list(dest.rglob('*.json')) == [dest / 'integration-manifest.json']
    assert all(p.stat().st_mode & 0o777 == 0o755 for p in dest.rglob('*') if p.is_dir())


def test_existing_destination_is_never_overwritten(tmp_path):
    sentinel = tmp_path / 'keep.txt'
    sentinel.write_text('existing contents')
    with pytest.raises(FileExistsError): stage_probe.stage(tmp_path)
    assert sentinel.read_text() == 'existing contents'
