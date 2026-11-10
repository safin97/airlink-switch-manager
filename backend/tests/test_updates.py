import copy
from datetime import datetime, timedelta, timezone
import json
import ssl
import threading

import pytest
from fastapi.testclient import TestClient

from airlink import updates
from airlink.app import Device, Settings, create_app
from airlink.board_probe import collect


def catalog(releases=None, age=0):
    return json.dumps({'schema_version': 1,
                      'generated_at': (datetime.now(timezone.utc) - timedelta(seconds=age)).isoformat(),
                      'releases': releases or []}).encode()


def release(**changes):
    result = {'product': 'CRS112-8P-4S-IN', 'architecture': 'mipsbe', 'board_revision': 'r2',
              'version': '1.2.0', 'sha256': 'a' * 64, 'size_bytes': 1024,
              'url': 'https://github.com/safin97/airlink-switch-manager/releases/download/test/test.bin'}
    result.update(changes)
    return result


BOARD = {'model': 'CRS112-8P-4S-IN', 'architecture': 'mipsbe', 'board_revision': 'r2', 'airlink_version': '1.0.0'}


@pytest.mark.parametrize('changes,status', [
    ({}, 'newer_metadata_available'),
    ({'board_revision': 'r4'}, 'no_matching_firmware'),
    ({'board_revision': None}, 'board_identity_incomplete'),
    ({'architecture': 'mipsel'}, 'board_identity_incomplete'),
    ({'model': 'CRS109'}, 'board_identity_incomplete'),
    ({'airlink_version': None}, 'installed_version_unavailable'),
    ({'airlink_version': '2.0.0'}, 'no_newer_metadata'),
    ({'airlink_version': '1.2.0'}, 'no_newer_metadata'),
])
def test_exact_identity_and_numeric_version_matching(changes, status):
    result = updates.CatalogClient(lambda: catalog([release()])).check(dict(BOARD, **changes))
    assert result['status'] == status
    assert result['installation_allowed'] is False and result['signature_verified'] is False


def test_empty_catalog_is_not_latest_application_or_up_to_date_claim():
    result = updates.CatalogClient(lambda: catalog()).check(BOARD)
    assert result['status'] == 'no_published_firmware' and result['candidate'] is None


def test_cache_failure_and_last_success_do_not_offer_old_candidate():
    ticks = [0]
    calls = []
    def fetch():
        calls.append(1)
        if len(calls) > 1:
            raise TimeoutError('internal network details')
        return catalog([release()])
    client = updates.CatalogClient(fetch, lambda: ticks[0])
    first = client.check(BOARD)
    client.check(BOARD)
    assert len(calls) == 1
    ticks[0] = 61
    failed = client.check(BOARD)
    assert failed['status'] == 'catalog_unavailable' and failed['stale']
    assert failed['last_success_at'] == first['last_success_at']
    assert failed['candidate'] is None and 'internal' not in json.dumps(failed)


@pytest.mark.parametrize('age', [8 * 86400, -3600])
def test_catalog_clock_limits(age):
    assert updates.CatalogClient(lambda: catalog(age=age)).check(BOARD)['status'] == 'catalog_stale'


def test_bad_schema_duplicates_overflow_and_untrusted_asset_hosts():
    bad = [b'[]', b'{' , b'x' * 65537,
           b'{"schema_version":1,"schema_version":1}',
           catalog([release(url='http://github.com/test.bin')]),
           catalog([release(url='https://evil.example/test.bin')]),
           catalog([release(architecture='arm')]), catalog([release(size_bytes=True)]),
           catalog([release(version='1.2.3;reboot')]), catalog([release(sha256='short')]),
           catalog([release(installation_allowed=True)]), catalog([release(), release()])]
    for raw in bad:
        assert updates.CatalogClient(lambda: raw).check(BOARD)['status'] == 'catalog_unavailable'


def test_single_catalog_request_in_flight():
    entered, finish = threading.Event(), threading.Event()
    def fetch():
        entered.set()
        assert finish.wait(2)
        return catalog()
    client = updates.CatalogClient(fetch)
    thread = threading.Thread(target=lambda: client.check(BOARD))
    thread.start()
    assert entered.wait(1)
    try:
        assert client.check(BOARD)['status'] == 'check_in_progress'
    finally:
        finish.set()
        thread.join()


def test_fixed_https_endpoint_no_credentials_redirects_or_oversize(monkeypatch):
    class Response:
        status = 200
        payload = catalog()
        headers = {}
        def getheader(self, key, default=None): return self.headers.get(key, default)
        def read1(self, size):
            chunk, self.payload = self.payload[:size], self.payload[size:]
            return chunk
    class Connection:
        def __init__(self, host, timeout, context):
            assert host == 'raw.githubusercontent.com' and timeout == 5
            assert context.verify_mode == ssl.CERT_REQUIRED and context.check_hostname
        def request(self, method, path, headers):
            assert method == 'GET' and path == updates.PATH
            assert set(headers) == {'Accept', 'User-Agent'}
        def getresponse(self): return Response()
        def close(self): pass
    monkeypatch.setattr(updates.http.client, 'HTTPSConnection', Connection)
    assert updates.parse_catalog(updates.fetch_catalog())['releases'] == []
    for status, headers, payload in [(302, {}, b''), (200, {'Content-Length': '999999'}, b''),
                                      (200, {}, b'x' * 65537), (200, {'Content-Length': '50'}, b'{}')]:
        Response.status, Response.headers, Response.payload = status, headers, payload
        with pytest.raises(ValueError): updates.fetch_catalog()


def test_authenticated_api_reads_board_without_writes_or_board_upload():
    token = 'test-only-online-check-0123456789012345'
    device = Device(id='switch', label='Switch', host='192.0.2.1', username='monitor',
                    expected_model=BOARD['model'], known_hosts='/unused')
    state = {'stale': False, 'verified': True}
    class Collector:
        def __init__(self, *args): pass
        def collect(self):
            return {'last_success_at': updates.now(), 'stale': state['stale'],
                    'device': dict(BOARD, verified=state['verified']),
                    'system': {'routeros_version': '6.48.6'}}
    calls = []
    def fetch(): calls.append(True); return catalog()
    app = create_app(Settings(token, [device]), Collector, catalog_client=updates.CatalogClient(fetch))
    path = '/api/v1/devices/switch/firmware/check'
    with TestClient(app, base_url='https://localhost') as client:
        assert client.get(path).status_code == 401 and not calls
        headers = {'Authorization': 'Bearer ' + token}
        result = client.get(path, headers=headers)
        assert result.status_code == 200 and calls == [True]
        body = result.json()
        assert body['board']['model'] == BOARD['model']
        assert body['board']['routeros_version'] == '6.48.6'
        assert body['board']['airlink_version'] is None
        assert body['installation_allowed'] is False
        assert client.post(path, headers=headers).status_code == 405
        assert client.get(path.replace('switch', 'missing'), headers=headers).status_code == 404
    state['stale'] = True
    with TestClient(create_app(Settings(token, [device]), Collector), base_url='https://localhost') as client:
        assert client.get(path, headers=headers).status_code == 409


def test_linux_probe_missing_fields_and_reported_values(tmp_path):
    empty = collect(tmp_path, machine='x86_64', byteorder='little')
    assert empty['board']['model'] is None and empty['system']['memory_total_bytes'] is None
    files = {'sys/firmware/devicetree/base/model': 'MikroTik CRS112-8P-4S\0',
             'sys/firmware/devicetree/base/compatible': 'test,board\0test,soc\0',
             'etc/os-release': 'ID=airlink\nVERSION_ID="1.0.0"\nPRETTY_NAME="AirLink test"',
             'proc/cpuinfo': 'cpu model : MIPS 24Kc\nSerial : do-not-publish',
             'proc/meminfo': 'MemTotal: 131072 kB\nMemAvailable: 60000 kB',
             'proc/uptime': '1234.5 4321.0'}
    for name, data in files.items():
        path = tmp_path / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_text(data)
    result = collect(tmp_path, machine='mips', byteorder='big')
    assert result['board']['model'] == BOARD['model'] and result['board']['architecture'] == 'mipsbe'
    assert result['board']['airlink_version'] == '1.0.0'
    assert result['board']['board_revision'] is None and not result['board']['identity_verified']
    assert result['system']['memory_total_bytes'] == 134217728
    assert result['system']['uptime_seconds'] == 1234.5
    assert 'do-not-publish' not in json.dumps(result)
    assert collect(tmp_path, machine='mips', byteorder='little')['board']['architecture'] is None


def test_probe_watch_reports_at_startup_without_installing_service(monkeypatch, capsys):
    from airlink import board_probe
    monkeypatch.setattr(board_probe.sys, 'platform', 'linux')
    monkeypatch.setattr(board_probe.sys, 'argv', ['probe', '--watch', '--check-online', '--interval', '300'])
    monkeypatch.setattr(board_probe, 'collect', lambda: {'board': copy.deepcopy(BOARD)})
    monkeypatch.setattr(board_probe, 'CatalogClient', lambda: updates.CatalogClient(lambda: catalog()))
    def stop(seconds): assert seconds == 300; raise KeyboardInterrupt()
    monkeypatch.setattr(board_probe.time, 'sleep', stop)
    board_probe.main()
    result = json.loads(capsys.readouterr().out)
    assert result['update_check']['status'] == 'no_published_firmware'
    assert result['update_check']['installation_allowed'] is False
