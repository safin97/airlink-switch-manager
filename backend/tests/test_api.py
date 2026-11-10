import threading
from fastapi.testclient import TestClient
from airlink.app import Device, Settings, create_app, DeviceMonitor
from airlink.collector import CollectionError, UnsupportedDevice

TOKEN = 'test-token-for-tests-only-0123456789'
DEVICE = Device(id='tower', label='Tower', host='192.0.2.10', username='monitor',
                expected_model='CRS318-16P-2S+OUT', known_hosts='/unused')


class FakeCollector:
    def __init__(self, *args): self.calls = 0
    def collect(self):
        self.calls += 1
        return {'last_success_at': '2026-11-10T12:00:00+00:00', 'stale': False, 'status': 'connected'}


def test_auth_transport_and_secret_redaction():
    app = create_app(Settings(TOKEN, [DEVICE]), FakeCollector)
    with TestClient(app, base_url='https://localhost') as client:
        for headers in [{}, {'Authorization': 'Bearer wrong'}]:
            assert client.get('/api/v1/devices', headers=headers).status_code == 401
            assert client.get('/api/v1/devices/tower/snapshot', headers=headers).status_code == 401
        headers = {'Authorization': f'Bearer {TOKEN}'}
        response = client.get('/api/v1/devices', headers=headers)
        assert response.status_code == 200
        assert response.headers['cache-control'] == 'no-store'
        assert response.json()['devices'] == [{'id': 'tower', 'label': 'Tower', 'expected_model': 'CRS318-16P-2S+OUT'}]
        assert '192.0.2.10' not in response.text and 'username' not in response.text
        assert client.get('/api/v1/devices/missing/snapshot', headers=headers).status_code == 404
        assert client.post('/api/v1/devices/tower/snapshot', headers=headers).status_code == 405
        assert client.get('/api/v1/devices/tower/snapshot', headers=headers).status_code == 200
    with TestClient(app) as client:
        assert client.get('/api/v1/devices', headers=headers).status_code == 400
        assert client.get('/api/v1/devices', headers={**headers, 'X-Forwarded-Proto': 'https'}).status_code == 400


def test_cached_failure_backoff_and_reconnect():
    collector = FakeCollector()
    monitor = DeviceMonitor(collector)
    first = monitor.snapshot()
    assert monitor.snapshot() == first and collector.calls == 1
    monitor.next_attempt = 0
    def fail(): raise CollectionError('command_timeout')
    collector.collect = fail
    stale = monitor.snapshot()
    assert stale['stale'] and stale['last_success_at'] == first['last_success_at']
    assert stale['error'] == 'command_timeout'
    assert monitor.snapshot() == stale
    monitor.next_attempt = 0
    collector.collect = lambda: first
    assert not monitor.snapshot()['stale']


def test_no_overlap():
    entered, release = threading.Event(), threading.Event()
    collector = FakeCollector()
    def slow(): entered.set(); release.wait(2); return {'stale': False}
    collector.collect = slow
    monitor = DeviceMonitor(collector)
    thread = threading.Thread(target=monitor.snapshot)
    thread.start(); assert entered.wait(1)
    try:
        from fastapi import HTTPException
        try: monitor.snapshot(); assert False
        except HTTPException as exc: assert exc.status_code == 503
    finally: release.set(); thread.join()


def test_model_mismatch_discards_cached_readings():
    monitor = DeviceMonitor(FakeCollector())
    monitor.snapshot(); monitor.next_attempt = 0
    def mismatch(): raise UnsupportedDevice('unsupported_or_mismatched_model')
    monitor.collector.collect = mismatch
    from fastapi import HTTPException
    try: monitor.snapshot(); assert False
    except HTTPException as exc: assert exc.status_code == 422
    assert monitor.cached is None
