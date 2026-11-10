import copy
import threading

import pytest
from fastapi.testclient import TestClient

from airlink.app import Device, Settings, create_app
from airlink.collector import CollectionError, EXPRESSIONS, UnsupportedDevice
from airlink.poe import ControlError, PoeControl
from test_collector import inventory

READ = 'monitor-token-test-only-0123456789012345'
WRITE = 'operator-token-test-only-01234567890123'


def device(small=True, enabled=True):
    return Device(id='test', label='Test', host='192.0.2.1', username='monitor',
                  known_hosts='/unused', expected_model='CRS112-8P-4S-IN' if small else 'CRS318-16P-2S+OUT',
                  poe_control_ports=['ether1'] if enabled else [],
                  control_username='operator', control_password_env='TEST_ROUTER_PASSWORD')


class Hardware:
    def __init__(self, small=True):
        self.small = small
        self.ports = inventory(small)
        self.serial = 'TEST-SERIAL'
        self.mode = 'forced-on'
        self.writes = []
        self.failure = None
        self.entered = threading.Event()
        self.release = threading.Event()
        self.block = False

    def session(self, credentials, environ):
        assert credentials.username == 'operator'
        hardware = self

        class Session:
            def __enter__(self): return self
            def __exit__(self, *args): pass
            def query(self, expression):
                if expression == EXPRESSIONS['resource']:
                    if hardware.failure == 'preflight': raise CollectionError('secret raw failure')
                    if hardware.block:
                        hardware.entered.set()
                        assert hardware.release.wait(3)
                    return [{'architecture-name': 'mipsbe' if hardware.small else 'arm'}]
                if expression == EXPRESSIONS['board']:
                    return [{'model': 'CRS112-8P-4S' if hardware.small else 'CRS318-16P-2S+',
                             'serial-number': hardware.serial, 'revision': 'r2'}]
                if expression == EXPRESSIONS['ethernet']: return copy.deepcopy(hardware.ports)
                if expression == '[/interface ethernet poe print as-value]':
                    return [{'name': hardware.ports[0]['name'], 'poe-out': hardware.mode}]
                raise AssertionError(expression)

            def execute(self, command):
                hardware.writes.append(command)
                if hardware.failure == 'write': raise CollectionError('secret connection details')
                assert 'poe-out=forced-on' not in command
                if hardware.failure != 'readback':
                    hardware.mode = 'auto-on' if 'poe-out=auto-on;' in command else 'off'
                return self.query('[/interface ethernet poe print as-value]')
        return Session()


@pytest.mark.parametrize('small', [True, False])
@pytest.mark.parametrize('mode', ['auto-on', 'off'])
def test_verified_mode_change_for_each_model_without_interpolating_names(small, mode):
    hw = Hardware(small)
    hw.ports[0]['name'] = 'x"; /system reboot; $name'
    ctl = PoeControl(device(small), {}, hw.session)
    prepared = ctl.prepare('ether1', hw.ports[0]['name'], mode)
    assert not hw.writes and prepared['previous_mode'] == 'forced-on'
    assert 'serial' not in str(prepared).lower()
    result = ctl.commit(prepared['confirmation_id'])
    assert result['configuration_mode'] == mode
    assert result['power_delivery_verified'] is False
    assert len(hw.writes) == 1 and hw.ports[0]['name'] not in hw.writes[0]
    assert 'default-name' in hw.writes[0]
    with pytest.raises(ControlError): ctl.commit(prepared['confirmation_id'])
    assert len(hw.writes) == 1


@pytest.mark.parametrize('change', ['serial', 'mode', 'name', 'id', 'expiry'])
def test_changed_or_expired_confirmation_never_writes(change):
    hw = Hardware()
    ctl = PoeControl(device(), {}, hw.session)
    prepared = ctl.prepare('ether1', hw.ports[0]['name'], 'off')
    if change == 'serial': hw.serial = 'replacement'
    if change == 'mode': hw.mode = 'auto-on'
    if change == 'name': hw.ports[0]['name'] = 'renamed'
    if change == 'id': hw.ports[0]['.id'] = '*FA'
    if change == 'expiry': ctl.pending['expires'] = 0
    with pytest.raises(ControlError): ctl.commit(prepared['confirmation_id'])
    assert not hw.writes and ctl.pending is None


@pytest.mark.parametrize('failure', ['write', 'readback'])
def test_unknown_outcome_consumes_confirmation_and_does_not_retry(failure):
    hw = Hardware(); ctl = PoeControl(device(), {}, hw.session)
    prepared = ctl.prepare('ether1', hw.ports[0]['name'], 'off')
    hw.failure = failure
    with pytest.raises(ControlError, match='') as error:
        ctl.commit(prepared['confirmation_id'])
    assert error.value.code == 'poe_outcome_unknown_refresh_before_retry'
    assert ctl.pending is None and len(hw.writes) == 1


def test_controls_fail_closed_for_unknown_modes_ids_and_ports():
    hw = Hardware(); ctl = PoeControl(device(), {}, hw.session)
    for port, mode in [('sfp9', 'off'), ('ether2', 'off'), ('ether1', 'forced-on')]:
        with pytest.raises(ControlError): ctl.prepare(port, hw.ports[0]['name'], mode)
    hw.mode = 'unavailable'
    with pytest.raises(ControlError): ctl.prepare('ether1', hw.ports[0]['name'], 'off')
    hw.mode = 'auto-on'; hw.serial = ''
    with pytest.raises(ControlError): ctl.prepare('ether1', hw.ports[0]['name'], 'off')
    hw.serial = 'TEST'; hw.ports[0]['.id'] = '*1; /system reboot'
    with pytest.raises(UnsupportedDevice): ctl.prepare('ether1', hw.ports[0]['name'], 'off')
    assert not hw.writes


class Monitor:
    def __init__(self, *args): self.calls = 0
    def collect(self):
        self.calls += 1
        return {'stale': False, 'status': 'connected', 'last_success_at': '2026-11-10T12:00:00Z'}


def api(hw, enabled=True):
    return create_app(Settings(READ, [device(enabled=enabled)], control_token=WRITE),
                      Monitor, lambda d, env: PoeControl(d, env, hw.session))


URL = '/api/v1/devices/test/poe/'
AUTH = {'Authorization': f'Bearer {WRITE}'}


def prepare_body(hw):
    return {'default_name': 'ether1', 'expected_name': hw.ports[0]['name'], 'mode': 'off'}


def test_api_permissions_transport_allowlist_and_explicit_confirmation():
    hw = Hardware()
    with TestClient(api(hw), base_url='https://localhost') as client:
        for token in ['', READ, 'wrong']:
            assert client.post(URL+'prepare', headers={'Authorization': f'Bearer {token}'},
                               json=prepare_body(hw)).status_code == 403
            assert client.post(URL+'commit', headers={'Authorization': f'Bearer {token}'},
                               json={'confirmed': True, 'confirmation_id': 'x'*43}).status_code == 403
        for body in [{**prepare_body(hw), 'mode': 'forced-on'},
                     {**prepare_body(hw), 'default_name': 'ether1; /system reboot'}]:
            assert client.post(URL+'prepare', headers=AUTH, json=body).status_code == 422
        assert client.post(URL+'prepare', headers=AUTH,
                           json={**prepare_body(hw), 'default_name': 'ether2'}).status_code == 403
        prepared = client.post(URL+'prepare', headers=AUTH, json=prepare_body(hw)).json()
        request = {'confirmed': False, 'confirmation_id': prepared['confirmation_id']}
        assert client.post(URL+'commit', headers=AUTH, json=request).status_code == 400
        assert not hw.writes
        request['confirmed'] = True
        assert client.post(URL+'commit', headers=AUTH, json=request).status_code == 200
        assert client.post(URL+'commit', headers=AUTH, json=request).status_code == 409
        assert len(hw.writes) == 1
    with TestClient(api(Hardware())) as client:
        assert client.post(URL+'prepare', headers=AUTH, json=prepare_body(hw)).status_code == 400
    with TestClient(api(Hardware(), enabled=False), base_url='https://localhost') as client:
        assert client.post(URL+'prepare', headers=AUTH, json=prepare_body(hw)).status_code == 403


def test_control_lock_blocks_overlapping_actions_and_marks_cached_reads_stale():
    hw = Hardware()
    with TestClient(api(hw), base_url='https://localhost') as client:
        read_headers = {'Authorization': f'Bearer {READ}'}
        snapshot_url = '/api/v1/devices/test/snapshot'
        assert client.get(snapshot_url, headers=read_headers).json()['stale'] is False
        hw.block = True
        responses = []
        thread = threading.Thread(target=lambda: responses.append(
            client.post(URL+'prepare', headers=AUTH, json=prepare_body(hw))))
        thread.start(); assert hw.entered.wait(1)
        try:
            assert client.post(URL+'prepare', headers=AUTH, json=prepare_body(hw)).status_code == 409
            assert client.get(snapshot_url, headers=read_headers).json()['stale'] is True
        finally:
            hw.release.set(); thread.join()
        assert responses[0].status_code == 200 and not hw.writes


def test_control_token_cannot_be_monitor_token():
    with pytest.raises(RuntimeError):
        create_app(Settings(READ, [device()], control_token=READ), Monitor)
    with pytest.raises(RuntimeError):
        create_app(Settings(READ, [device()]), Monitor)


def test_api_does_not_expose_raw_failure_details():
    hw = Hardware(); hw.failure = 'preflight'
    with TestClient(api(hw), base_url='https://localhost') as client:
        result = client.post(URL+'prepare', headers=AUTH, json=prepare_body(hw))
        assert result.status_code == 503 and 'secret' not in result.text
        hw.failure = None
        nonce = client.post(URL+'prepare', headers=AUTH, json=prepare_body(hw)).json()['confirmation_id']
        hw.failure = 'write'
        result = client.post(URL+'commit', headers=AUTH, json={'confirmed': True, 'confirmation_id': nonce})
        assert result.status_code == 502 and 'secret' not in result.text
        assert len(hw.writes) == 1
