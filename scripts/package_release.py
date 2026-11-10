#!/usr/bin/env python3
"""Package existing host-app builds and explicitly selected backend files.

Does not build, upload, sign, flash, or create router firmware. Run after validation.
Never includes local router configuration, credentials, caches, or virtual environments.
"""
import hashlib
import json
import re
import shutil
import subprocess
import tempfile
import zipfile
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def source_files():
    """Select project source, never runtime configuration or generated caches."""
    files = [ROOT/p for p in ['README.md', 'pubspec.yaml', 'pubspec.lock',
                             'analysis_options.yaml', '.gitignore', '.metadata']]
    excluded_dirs = {'build', 'Pods', 'ephemeral', '.gradle', '.symlinks',
                     'xcuserdata', '__pycache__', '.dart_tool', '.venv', '.git'}
    excluded_names = {'local.properties', 'Generated.xcconfig',
                      'flutter_export_environment.sh', '.DS_Store', 'key.properties'}
    for folder in ['lib', 'test', 'integration_test', 'test_driver', 'scripts', 'docs',
                   'firmware', '.vscode', 'android', 'ios', 'macos', 'linux', 'windows', 'web']:
        for p in (ROOT/folder).rglob('*'):
            if p.is_symlink() or not p.is_file():
                continue
            relative = p.relative_to(ROOT)
            if excluded_dirs.intersection(relative.parts) or p.name in excluded_names:
                continue
            if (p.name.startswith('.env') or 'known_hosts' in p.name or
                    p.suffix in {'.pem', '.key', '.p12', '.pfx', '.jks', '.keystore', '.iml', '.pyc', '.log'}):
                continue
            files.append(p)
    files += sorted((ROOT/'backend/airlink').glob('*.py'))
    files += sorted((ROOT/'backend/tests').glob('*.py'))
    files += [ROOT/p for p in ['backend/requirements.txt', 'backend/requirements-lock.txt',
                              'backend/devices.example.json', 'backend/.env.example',
                              'backend/Caddyfile.example']]
    for p in files:
        if p.is_symlink() or not p.resolve().is_relative_to(ROOT):
            raise SystemExit('Unexpected symlink or external source path')
    return sorted(set(files))


def main():
    version = re.search(r'^version:\s*(\S+)', (ROOT/'pubspec.yaml').read_text(), re.M)[1]
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    destination = ROOT/'dist'/f'airlink-{version}-development-{stamp}'
    app = ROOT/'build/macos/Build/Products/Release/AirLink.app'
    web = ROOT/'build/web'
    if not (app/'Contents/MacOS/AirLink').is_file() or not (web/'main.dart.js').is_file():
        raise SystemExit('First run flutter build macos --release and flutter build web.')
    destination.mkdir(parents=True, exist_ok=False)
    mac = destination/'airlink-macos.zip'
    # Stage outside Desktop file-provider storage. Copy bytes, permissions and
    # relative framework symlinks without Finder/resource-fork metadata. Do not
    # alter Gatekeeper settings or quarantine policy on the user's machine.
    with tempfile.TemporaryDirectory(prefix='airlink-package-', dir='/tmp') as temp:
        staged = Path(temp)/'AirLink.app'
        shutil.copytree(app, staged, symlinks=True, copy_function=shutil.copy)
        subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(staged)], check=True)
        architectures = subprocess.check_output(
            ['/usr/bin/lipo', '-archs', str(staged/'Contents/MacOS/AirLink')], text=True).split()
        subprocess.run(['/usr/bin/ditto', '-c', '-k', '--norsrc', '--noextattr', '--keepParent',
                        str(staged), str(mac)], check=True)
        extracted = Path(temp)/'roundtrip'
        subprocess.run(['/usr/bin/ditto', '-x', '-k', str(mac), str(extracted)], check=True)
        subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict',
                        str(extracted/'AirLink.app')], check=True)
    # Explicit paths: no recursive copy of backend/ or the user's configuration.
    backend_files = sorted((ROOT/'backend/airlink').glob('*.py')) + [ROOT/p for p in [
        'backend/requirements.txt', 'backend/requirements-lock.txt',
        'backend/devices.example.json', 'backend/.env.example',
        'backend/Caddyfile.example', 'README.md', 'docs/API.md', 'docs/VALIDATION.md',
        'firmware/UPDATE-PROTOCOL.md']]
    web_files = sorted(p for p in web.rglob('*') if p.is_file())
    for p in backend_files + web_files:
        if p.is_symlink() or not p.resolve().is_relative_to(ROOT):
            raise SystemExit(f'Unexpected symlink or external path: {p.name}')
    service = destination/'airlink-web-backend.zip'
    with zipfile.ZipFile(service, 'x', compression=zipfile.ZIP_DEFLATED) as archive:
        for p in backend_files:
            archive.write(p, str(p.relative_to(ROOT)))
        for p in web_files:
            archive.write(p, 'web/'+str(p.relative_to(web)))
        archive.writestr('START-HERE.txt',
            'AIRLINK DEVELOPMENT PACKAGE — HOST SOFTWARE, NOT SWITCH FIRMWARE\n\n'
            'Python backend: follow README.md Backend setup, using the included backend/ directory.\n'
            'Create a fresh virtual environment and install backend/requirements.txt.\n'
            'Supply router credentials and verified host keys privately on the backend.\n'
            'PoE control is disabled by default; configure approved ports and separate credentials.\n'
            'Serve web/ using an HTTPS static web server. Configure the backend HTTPS origin\n'
            'in the app and exact web origin in AIRLINK_CORS_ORIGINS.\n'
            'Desktop app is supplied separately in airlink-macos.zip.\n'
            'The macOS app has an ad-hoc signature, no Developer ID or notarization.\n'
            'Live monitoring/PoE behavior remains unverified on physical switches.\n'
            'Do not upload either archive to RouterOS or use it as sysupgrade firmware.\n')
    source = destination/'airlink-source.zip'
    sources = source_files()
    with zipfile.ZipFile(source, 'x', compression=zipfile.ZIP_DEFLATED) as archive:
        for p in sources:
            archive.write(p, str(Path('airlink-switch-manager')/p.relative_to(ROOT)))
    for archive in [mac, service, source]:
        with zipfile.ZipFile(archive) as z:
            if z.testzip() is not None:
                raise SystemExit(f'Archive integrity check failed: {archive.name}')
    manifest = {
        'version': version, 'created_at': stamp, 'release_class': 'development',
        'published_remotely': False,
        'macos': {'architectures': architectures, 'signing': 'ad-hoc', 'notarized': False,
                  'archive_roundtrip_signature_verified': True},
        'artifacts': [{'name': p.name, 'bytes': p.stat().st_size, 'sha256': digest(p)}
                      for p in [mac, service, source]],
        'source_input_hashes': {str(p.relative_to(ROOT)): digest(p) for p in sources},
        'backend_input_hashes': {str(p.relative_to(ROOT)): digest(p) for p in backend_files},
        'firmware': {board: json.loads((ROOT/'firmware'/board/'board-status.json').read_text())
                     for board in ['crs112', 'netpower16p']},
        'firmware_images_included': False,
        'limitations': ['No live-device validation', 'No installable kernel or sysupgrade image',
                        'Other native platform binaries are not included'],
    }
    (destination/'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
    (destination/'SHA256SUMS').write_text(''.join(
        f"{item['sha256']}  {item['name']}\n" for item in manifest['artifacts']))
    (ROOT/'dist/LATEST.txt').write_text(destination.name+'\n')
    print(destination)


if __name__ == '__main__':
    main()
