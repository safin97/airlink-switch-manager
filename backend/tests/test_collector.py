from types import SimpleNamespace
import pytest
from airlink.collector import (CollectionError, Collector, RateTracker, UnsupportedDevice,
                               parse_frames, number, counter, detect_model, validate_ports,
                               uptime_seconds, SSHSession)


def frames(rows):
    out = ['ALBEGIN']
    for row in rows:
        out.append('ALREC')
        for key, value in row.items():
            escaped = str(value).replace('%', '%25').replace('\n', '%0A').replace('\r', '%0D').replace('\t', '%09')
            out.append(f'AL1\t{key}\t{escaped}')
        out.append('ALENDREC')
    return '\r\n'.join(out + ['ALDONE'])


def inventory(small=False):
    names = [f'ether{i}' for i in range(1, 9 if small else 17)]
    names += [f'sfp{i}' for i in range(9, 13)] if small else ['sfp-sfpplus1', 'sfp-sfpplus2']
    return [{'.id': f'*{i+1:X}', 'name': f'custom port {i}', 'default-name': name, 'disabled': 'false'} for i, name in enumerate(names)]


def test_framing_reserved_characters_and_unicode():
    rows = [{'name': 'uplink = ; " café\n%0A\t', '.id': '*1', 'rx-byte': '18446744073709551615'}]
    assert parse_frames(frames(rows)) == rows
    assert counter(rows[0]['rx-byte']) == 18446744073709551615


@pytest.mark.parametrize('text', ['ALBEGIN\nALREC\nAL1\tname\tfoo', 'syntax error',
    'ALBEGIN\nALREC\nAL1\tx\t1\nAL1\tx\t2\nALENDREC\nALDONE',
    'ALBEGIN\nAL1\tx\t1\nALDONE', 'ALBEGIN\nALREC\nALDONE'])
def test_rejects_partial_or_ambiguous_responses(text):
    with pytest.raises(CollectionError): parse_frames(text)


@pytest.mark.parametrize('value,unit,expected', [('500mA','A',.5), ('500','A',.5), ('48.2V','V',48.2), ('8000mW','W',8), ('10Gbps','Mbps',10000), ('128MiB','bytes',134217728), ('42C','C',42), ('unknown','V',None), ('2mA','V',None), ('542','V',None), ('243','W',None)])
def test_units(value, unit, expected):
    assert number(value, unit) == expected


def test_rates_resets_and_precision():
    tracker = RateTracker()
    def sample(rx, tx): return [{'id': '*1', 'default_name': 'ether1', 'rx_bytes': rx, 'tx_bytes': tx}]
    base = 2 ** 60
    ports = sample(base, 0)
    tracker.update(ports, 10, 100)
    assert ports[0]['rx_mbps'] is None
    ports = sample(base + 1_000_000, 500_000)
    tracker.update(ports, 12, 102)
    assert ports[0]['rx_mbps'] == 4 and ports[0]['tx_mbps'] == 2
    ports = sample(2, 3)
    tracker.update(ports, 14, 104)
    assert ports[0]['rx_mbps'] is None and ports[0]['counter_reset']
    ports = sample(8_000_000, 8_000_000)
    tracker.update(ports, 16, 1)
    assert ports[0]['rx_mbps'] is None  # reboot, even if counters grew
    tracker.update(ports, 16, 1)
    assert ports[0]['tx_mbps'] is None  # no elapsed time


def test_missing_counter_does_not_create_zero_rate():
    tracker = RateTracker()
    p = [{'id': '*1', 'default_name': 'ether1', 'rx_bytes': None, 'tx_bytes': None}]
    tracker.update(p, 1, 1)
    tracker.update(p, 5, 5)
    assert p[0]['rx_mbps'] is None


@pytest.mark.parametrize('model,arch,small', [('CRS318-16P-2S+OUT','arm',False),('CRS112-8P-4S-IN','mipsbe',True)])
def test_actual_identity_and_renamed_interfaces(model, arch, small):
    assert detect_model({'model': model}, {'architecture-name': arch}, model) == model
    assert len(validate_ports(inventory(small), model)) == (12 if small else 18)
    with pytest.raises(UnsupportedDevice): detect_model({'model': 'CRS328-24P-4S+'}, {'architecture-name': arch}, model)
    with pytest.raises(UnsupportedDevice): detect_model({'model': model}, {'architecture-name': 'arm64'}, model)
    with pytest.raises(UnsupportedDevice): validate_ports(inventory(small)[:-1], model)
    rows = inventory(small); rows[0]['.id'] = '*1; /system reboot'
    with pytest.raises(UnsupportedDevice): validate_ports(rows, model)


@pytest.mark.parametrize('value,result', [('1w2d3h4m5s',788645),('1d03:04:05',97445),('1h',3600),('',None),('invalid',None)])
def test_uptime(value, result): assert uptime_seconds(value) == result


class FakeSession:
    fail_health = False
    fail_counters = False
    small = False
    def __init__(self, *args): pass
    def __enter__(self): return self
    def __exit__(self, *args): pass
    def query(self, expression):
        small = self.small
        if 'system resource' in expression:
            return [{'architecture-name': 'mipsbe' if small else 'arm', 'cpu-load': '12', 'uptime': '1d', 'free-memory': '123456', 'total-memory': '256000000', 'version': '6.49.18'}]
        if 'system routerboard' in expression: return [{'model': 'CRS112-8P-4S' if small else 'CRS318-16P-2S+', **({'revision': 'r2'} if small else {})}]
        if 'system identity' in expression: return [{'name': 'Switch'}]
        if 'ethernet print' in expression: return inventory(small)
        if 'print stats' in expression:
            if self.fail_counters: raise CollectionError('unsupported_command')
            return [{'name': p['name'], 'rx-byte': '12345678', 'tx-byte': '123456'} for p in inventory(small)]
        if 'system health' in expression:
            if self.fail_health: raise CollectionError('unsupported_command')
            return [{'name': 'cpu-temperature', 'value': '43', 'type': 'C'}]
        if 'poe monitor' in expression: return [{'poe-out-status': 'powered-on', 'poe-out-voltage': '48V', 'poe-out-current': '150mA', 'poe-out-power': '7.2W'}]
        if 'ethernet monitor' in expression: return [{'status': 'link-ok', 'rate': '1Gbps', 'full-duplex': 'yes'}]
        raise AssertionError(expression)


@pytest.mark.parametrize('small', [False,True])
def test_collector_normalizes_both_models(small):
    class Session(FakeSession): pass
    Session.small = small
    device = SimpleNamespace(id='test', expected_model='CRS112-8P-4S-IN' if small else 'CRS318-16P-2S+OUT')
    result = Collector(device, {}, Session).collect()
    assert result['mode'] == 'live' and result['device']['verified']
    assert result['device']['board_revision'] == ('r2' if small else None)
    assert len(result['ports']) == (12 if small else 18)
    assert result['ports'][0]['poe']['current_a'] == .15
    assert result['ports'][-1]['poe']['voltage_v'] is None
    assert result['ports'][0]['rx_mbps'] is None
    assert result['system']['temperatures'][0]['celsius'] == 43


def test_optional_failures_preserve_other_sections_without_fabrication():
    class Partial(FakeSession):
        fail_health = fail_counters = True
    result = Collector(SimpleNamespace(id='test', expected_model='CRS318-16P-2S+OUT'), {}, Partial).collect()
    assert result['status'] == 'partial' and len(result['warnings']) == 2
    assert result['system']['temperatures'] == []
    assert result['ports'][0]['rx_bytes'] is None
    assert result['ports'][0]['counters_at'] is None
    assert result['ports'][0]['speed_mbps'] == 1000


def test_verified_host_key_policy_and_no_agent(monkeypatch):
    import paramiko
    class Client:
        def load_host_keys(self, path): assert path == '/trusted/hosts'
        def set_missing_host_key_policy(self, policy): assert isinstance(policy, paramiko.RejectPolicy)
        def connect(self, *args, **kw):
            assert kw['allow_agent'] is False and kw['look_for_keys'] is False
            raise paramiko.AuthenticationException('raw secret must never escape')
        def close(self): pass
    monkeypatch.setattr(paramiko, 'SSHClient', Client)
    device = SimpleNamespace(known_hosts='/trusted/hosts', host='example', port=22, username='monitor', password_env='SECRET', key_file=None)
    with pytest.raises(CollectionError, match='^router_authentication_failed$'):
        with SSHSession(device, {'SECRET': 'sensitive'}): pass


def test_map_with_nested_monitor_properties_is_not_treated_as_rows():
    from airlink.collector import script
    command = script("[/interface ethernet monitor *1 once as-value]")
    assert '[:typeof ($rows->0)] = "array"' in command
    assert ':local nested false' not in command


def test_counter_serialization_is_lossless_for_web_clients():
    result = Collector(SimpleNamespace(id='test', expected_model='CRS318-16P-2S+OUT'), {}, FakeSession).collect()
    assert result['ports'][0]['rx_bytes'] == '12345678'
