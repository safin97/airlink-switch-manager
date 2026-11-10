"""Launch a real local API with no routers and exercise auth; prints no secrets."""
import json
import os
from pathlib import Path
import secrets
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='airlink-smoke-') as directory:
    config = Path(directory) / 'devices.json'
    config.write_text('{"devices": []}')
    token = secrets.token_urlsafe(32)
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]
    env = {**os.environ, 'AIRLINK_CONFIG': str(config), 'AIRLINK_API_TOKEN': token,
           'AIRLINK_ALLOW_LOOPBACK_HTTP': '1'}
    process = subprocess.Popen([sys.executable, '-m', 'uvicorn', 'airlink.app:create_app',
        '--factory', '--host', '127.0.0.1', '--port', str(port), '--workers', '1',
        '--no-proxy-headers', '--no-access-log'], cwd=root / 'backend', env=env,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        url = f'http://127.0.0.1:{port}/api/v1/devices'
        ready = False
        for _ in range(100):
            try:
                urllib.request.urlopen(url, timeout=.2)
            except urllib.error.HTTPError as exc:
                assert exc.code == 401
                ready = True
                break
            except urllib.error.URLError:
                time.sleep(.05)
        assert ready, 'API did not become ready'
        request = urllib.request.Request(url, headers={'Authorization': 'Bearer ' + token})
        with urllib.request.urlopen(request, timeout=3) as response:
            assert response.status == 200
            assert json.load(response) == {'devices': []}
        print('PASS: real uvicorn process rejects unauthenticated access and serves authenticated profiles. No routers configured or contacted.')
    finally:
        process.terminate()
        process.wait(timeout=5)
