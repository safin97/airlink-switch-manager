"""Explicit, single-use PoE actions, separate from the read-only collector."""
from __future__ import annotations

import hashlib
import json
import re
import secrets
import time

from .collector import (CollectionError, EXPRESSIONS, SSHSession, detect_model,
                        script, utc, validate_ports)


class ControlError(Exception):
    def __init__(self, status, code):
        self.status, self.code = status, code


class PoeControl:
    def __init__(self, device, environ, session_factory=SSHSession):
        self.device = device
        self.credentials = device.model_copy(update={
            'username': device.control_username,
            'password_env': device.control_password_env,
            'key_file': device.control_key_file,
        })
        self.environ, self.session_factory = environ, session_factory
        self.pending = None  # one bounded, expiring confirmation per device

    def inspect(self, session, default_name, expected_name):
        resources = session.query(EXPRESSIONS['resource'])
        boards = session.query(EXPRESSIONS['board'])
        if len(resources) != 1 or len(boards) != 1:
            raise CollectionError('identity_response_incomplete')
        model = detect_model(boards[0], resources[0], self.device.expected_model)
        if not boards[0].get('serial-number'):
            raise ControlError(409, 'board_identity_unavailable')
        ports = validate_ports(session.query(EXPRESSIONS['ethernet']), model)
        port = next((p for p in ports if p['default-name'] == default_name), None)
        if not port or not re.fullmatch(r'ether[1-9][0-9]*', default_name):
            raise ControlError(422, 'not_a_copper_poe_port')
        if port['name'] != expected_name:
            raise ControlError(409, 'interface_changed_refresh_before_control')
        # Use the PoE menu to establish actual configuration support. Names are
        # obtained on the router, never interpolated from a request into its script.
        rows = session.query('[/interface ethernet poe print as-value]')
        matches = [p for p in rows if p.get('name') == port['name']]
        if len(matches) != 1 or matches[0].get('poe-out') not in {'auto-on', 'off', 'forced-on'}:
            raise ControlError(422, 'poe_configuration_unavailable')
        mode = matches[0]['poe-out']
        identity = [model, boards[0]['serial-number'], boards[0].get('revision'),
                    port['.id'], port['default-name'], port['name'], mode]
        fingerprint = hashlib.sha256(json.dumps(identity).encode()).hexdigest()
        return port, mode, fingerprint

    def prepare(self, default_name, expected_name, mode):
        if default_name not in self.device.poe_control_ports:
            raise ControlError(403, 'port_control_not_permitted')
        if mode not in {'auto-on', 'off'}:
            raise ControlError(422, 'unsupported_poe_action')
        with self.session_factory(self.credentials, self.environ) as session:
            port, before, fingerprint = self.inspect(session, default_name, expected_name)
        nonce = secrets.token_urlsafe(32)
        self.pending = dict(nonce=nonce, expires=time.monotonic()+60,
                            default_name=default_name, name=expected_name,
                            mode=mode, fingerprint=fingerprint)
        return {'confirmation_id': nonce, 'expires_in_seconds': 60,
                'device_id': self.device.id, 'device_label': self.device.label,
                'port': port['default-name'], 'name': port['name'],
                'previous_mode': before, 'requested_mode': mode,
                'prepared_at': utc(),
                'warning': 'Changing PoE can power off a connected device and disconnect '
                           'your management connection. The management path is not detected. '
                           'Auto-on uses detection and does not guarantee power delivery. '
                           'Changing an existing forced-on port to auto-on may interrupt power.'}

    def commit(self, nonce):
        pending = self.pending
        if not pending or not secrets.compare_digest(nonce, pending['nonce']):
            raise ControlError(409, 'confirmation_invalid_or_already_used')
        self.pending = None  # consume before connecting; never retry a write
        if time.monotonic() >= pending['expires']:
            raise ControlError(409, 'confirmation_expired')
        with self.session_factory(self.credentials, self.environ) as session:
            port, before, fingerprint = self.inspect(
                session, pending['default_name'], pending['name'])
            if fingerprint != pending['fingerprint']:
                raise ControlError(409, 'device_or_poe_configuration_changed')
            internal_id, mode = port['.id'], pending['mode']
            # validate_ports verified ID syntax; mode is a server-owned enum.
            # Recheck mode at the write site as well as in the preflight.
            name = f'[/interface ethernet get {internal_id} name]'
            command = (
                f':if ([/interface ethernet get {internal_id} default-name] != "{pending["default_name"]}") '
                'do={ :error "Interface changed" };\n'
                f':if ([/interface ethernet poe get {name} poe-out] != "{before}") '
                'do={ :error "PoE configuration changed" };\n'
                f'/interface ethernet poe set {name} poe-out={mode};\n'
                + script('[/interface ethernet poe print as-value]'))
            try:
                rows = session.execute(command)
                actual = [p for p in rows if p.get('name') == port['name']]
                if len(actual) != 1 or actual[0].get('poe-out') != mode:
                    raise CollectionError('poe_readback_failed')
            except (CollectionError, OSError):
                # A timeout can mean the power was already changed. Never report
                # definite failure, roll back, power-cycle or replay automatically.
                raise ControlError(502, 'poe_outcome_unknown_refresh_before_retry') from None
        return {'status': 'configuration_verified', 'device_id': self.device.id,
                'port': port['default-name'], 'configuration_mode': mode,
                'verified_at': utc(), 'power_delivery_verified': False}
