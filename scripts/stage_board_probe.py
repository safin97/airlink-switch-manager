#!/usr/bin/env python3
"""Stage a generic Linux development overlay, never a board firmware image.

Does not install a service, select a board target, build a kernel or flash a device.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]


def stage(destination):
    destination = Path(destination)
    destination.mkdir(parents=True, exist_ok=False)
    files = {
        **{f'backend/airlink/{name}': f'usr/lib/airlink-board-probe/airlink/{name}'
           for name in ['__init__.py', 'board_probe.py', 'updates.py']},
        'firmware/integration/linux/launcher.py': 'usr/lib/airlink-board-probe/launcher.py',
        'firmware/integration/linux/airlink-board-probe.service': 'usr/lib/systemd/system/airlink-board-probe.service',
        'firmware/integration/linux/README.md': 'usr/share/doc/airlink-board-probe/README.md',
    }
    manifest = {'artifact_type': 'generic-linux-development-overlay',
                'target_board': None, 'installable_switch_firmware': False,
                'service_enabled': False, 'files': {}}
    for source, target in files.items():
        src, dst = ROOT / source, destination / target
        if src.is_symlink():
            raise ValueError('Symlink source rejected')
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, dst)
        dst.chmod(0o644)
        manifest['files'][target] = {'bytes': dst.stat().st_size,
            'sha256': hashlib.sha256(dst.read_bytes()).hexdigest()}
    (destination / 'integration-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    for directory in [destination, *(p for p in destination.rglob('*') if p.is_dir())]:
        directory.chmod(0o755)
    (destination / 'integration-manifest.json').chmod(0o644)
    return manifest


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path, help='New empty staging directory; must not already exist')
    args = parser.parse_args()
    stage(args.output)
    print(args.output)
