"""Read-only release discovery. HTTPS metadata never authorizes installation."""
from __future__ import annotations

import copy
from datetime import datetime, timezone
import http.client
import json
import re
import ssl
import threading
import time

HOST = 'raw.githubusercontent.com'
PATH = '/safin97/airlink-switch-manager/main/firmware/catalog.json'
CATALOG_URL = 'https://' + HOST + PATH
PRODUCTS = {'CRS112-8P-4S-IN': 'mipsbe', 'CRS318-16P-2S+OUT': 'arm'}
LIMIT = 65536


def now():
    return datetime.now(timezone.utc).isoformat()


def timestamp(value):
    if not isinstance(value, str):
        raise ValueError('invalid_timestamp')
    parsed = datetime.fromisoformat(value.replace('Z', '+00:00'))
    if parsed.tzinfo is None:
        raise ValueError('timezone_required')
    return parsed


def version(value):
    if not isinstance(value, str) or not re.fullmatch(r'[0-9]{1,6}\.[0-9]{1,6}\.[0-9]{1,6}', value):
        raise ValueError('unsupported_version')
    return tuple(int(p) for p in value.split('.'))


def fetch_catalog():
    # No credentials, board identifiers, proxy environment, caller URLs or redirects.
    connection = http.client.HTTPSConnection(HOST, timeout=5, context=ssl.create_default_context())
    deadline = time.monotonic() + 15
    try:
        connection.request('GET', PATH, headers={'Accept': 'application/json',
                                               'User-Agent': 'AirLink-ReadOnly-Check/1'})
        response = connection.getresponse()
        if response.status != 200 or response.getheader('Content-Encoding', 'identity') != 'identity':
            raise ValueError('catalog_http_error')
        length = response.getheader('Content-Length')
        if length is not None and (not length.isdigit() or int(length) > LIMIT):
            raise ValueError('catalog_size_error')
        data = bytearray()
        while True:
            if time.monotonic() > deadline:
                raise TimeoutError('catalog_deadline')
            chunk = response.read1(min(4096, LIMIT + 1 - len(data)))
            if not chunk:
                break
            data.extend(chunk)
            if len(data) > LIMIT:
                raise ValueError('catalog_size_error')
        if length is not None and len(data) != int(length):
            raise ValueError('catalog_truncated')
        return bytes(data)
    finally:
        connection.close()


def parse_catalog(raw):
    if not isinstance(raw, bytes) or len(raw) > LIMIT:
        raise ValueError('catalog_size_error')
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError('duplicate_catalog_key')
            result[key] = value
        return result
    catalog = json.loads(raw, object_pairs_hook=unique)
    if (not isinstance(catalog, dict) or set(catalog) != {'schema_version', 'generated_at', 'releases'}
            or type(catalog['schema_version']) is not int or catalog['schema_version'] != 1
            or not isinstance(catalog['releases'], list) or len(catalog['releases']) > 100):
        raise ValueError('invalid_catalog')
    timestamp(catalog['generated_at'])
    seen = set()
    for item in catalog['releases']:
        if not isinstance(item, dict) or set(item) != {
                'product', 'architecture', 'board_revision', 'version', 'sha256', 'size_bytes', 'url'}:
            raise ValueError('invalid_release')
        if (not all(isinstance(item[k], str) for k in ['product', 'architecture', 'board_revision', 'version', 'sha256', 'url'])
                or PRODUCTS.get(item['product']) != item['architecture']
                or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._+-]{0,63}', item['board_revision'])
                or not re.fullmatch(r'[a-f0-9]{64}', item['sha256'])
                or type(item['size_bytes']) is not int or not 0 < item['size_bytes'] < 2**32
                or not re.fullmatch(r'https://github\.com/safin97/airlink-switch-manager/releases/download/[A-Za-z0-9_+.-]{1,100}/[A-Za-z0-9_+.-]{1,100}\.bin', item['url'])):
            raise ValueError('invalid_release')
        v = version(item['version'])
        key = (item['product'], item['board_revision'], v)
        if key in seen:
            raise ValueError('duplicate_release')
        seen.add(key)
    return catalog


class CatalogClient:
    def __init__(self, fetch=fetch_catalog, clock=time.monotonic):
        self.fetch, self.clock = fetch, clock
        self.lock = threading.Lock()
        self.cached = None
        self.last_success = None
        self.last_attempt = None
        self.next_attempt = 0
        self.failed = False

    def check(self, board):
        if not self.lock.acquire(blocking=False):
            return self._result(board, None, 'check_in_progress', True)
        try:
            if self.clock() >= self.next_attempt:
                self.last_attempt = now()
                try:
                    self.cached = parse_catalog(self.fetch())
                    self.last_success = now()
                    self.failed = False
                except (OSError, ValueError, http.client.HTTPException, RecursionError):
                    self.failed = True
                self.next_attempt = self.clock() + 60
            if self.failed:
                return self._result(board, None, 'catalog_unavailable', True)
            age = (datetime.now(timezone.utc) - timestamp(self.cached['generated_at'])).total_seconds()
            if not -300 <= age <= 7 * 86400:
                return self._result(board, None, 'catalog_stale', True)
            releases = self.cached['releases']
            if not releases:
                return self._result(board, None, 'no_published_firmware', False)
            if (board.get('model') not in PRODUCTS or
                    board.get('architecture') != PRODUCTS[board['model']] or
                    not isinstance(board.get('board_revision'), str) or not board['board_revision']):
                return self._result(board, None, 'board_identity_incomplete', False)
            matches = [r for r in releases if r['product'] == board['model']
                       and r['architecture'] == board['architecture'] and r['board_revision'] == board['board_revision']]
            if not matches:
                return self._result(board, None, 'no_matching_firmware', False)
            latest = max(matches, key=lambda r: version(r['version']))
            try:
                current = version(board.get('airlink_version'))
            except ValueError:
                return self._result(board, latest, 'installed_version_unavailable', False)
            state = 'newer_metadata_available' if version(latest['version']) > current else 'no_newer_metadata'
            return self._result(board, latest, state, False)
        finally:
            self.lock.release()

    def _result(self, board, candidate, status, stale):
        return {'schema_version': 1, 'board': copy.deepcopy(board), 'status': status,
                'checked_at': now(), 'last_attempt_at': self.last_attempt,
                'last_success_at': self.last_success, 'catalog_url': CATALOG_URL,
                'catalog_generated_at': self.cached['generated_at'] if self.cached else None,
                'stale': stale, 'candidate': copy.deepcopy(candidate),
                'installation_allowed': False, 'signature_verified': False}
