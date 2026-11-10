"""Linux read-only prototype; no drivers, flashing, shell commands or HTTP server."""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import platform
import shlex
import sys
import time

from .updates import CatalogClient, now


def collect(root=Path('/'), machine=None, byteorder=None):
    def read(name):
        try:
            with (root / name).open('rb') as stream:
                raw = stream.read(65537)
            return raw.decode('utf-8').strip('\x00\n ') if len(raw) <= 65536 else None
        except (OSError, UnicodeError):
            return None
    model = read('sys/firmware/devicetree/base/model')
    compatible = read('sys/firmware/devicetree/base/compatible')
    cpu = read('proc/cpuinfo')
    memory = read('proc/meminfo')
    os_data = read('etc/os-release')
    os_fields = {}
    for line in (os_data or '').splitlines():
        key, sep, value = line.partition('=')
        if sep and key in {'ID', 'VERSION_ID', 'PRETTY_NAME'}:
            try:
                parts = shlex.split(value, comments=False)
                if len(parts) == 1:
                    os_fields[key] = parts[0]
            except ValueError:
                pass
    machine = machine or platform.machine()
    byteorder = byteorder or sys.byteorder
    arch = 'mipsbe' if machine in {'mips', 'mips32'} and byteorder == 'big' else (
        'arm' if machine in {'armv7l', 'armv6l'} else None)
    # Exact label matching only; even a match is a report, not PCB verification.
    aliases = {'CRS112-8P-4S': 'CRS112-8P-4S-IN', 'CRS112-8P-4S-IN': 'CRS112-8P-4S-IN',
               'CRS318-16P-2S+OUT': 'CRS318-16P-2S+OUT'}
    normalized = model.removeprefix('MikroTik ') if model else None
    def mem_value(key):
        for line in (memory or '').splitlines():
            parts = line.split()
            if len(parts) == 3 and parts[0] == key + ':' and parts[1].isdigit() and parts[2] == 'kB':
                return int(parts[1]) * 1024
        return None
    try:
        uptime = float((read('proc/uptime') or '').split()[0])
        if not math.isfinite(uptime) or uptime < 0:
            uptime = None
    except (ValueError, IndexError):
        uptime = None
    cpu_model = None
    for line in (cpu or '').splitlines():
        key, sep, value = line.partition(':')
        if sep and key.strip() in {'cpu model', 'model name'}:
            cpu_model = value.strip()
            break
    return {'schema_version': 1, 'observed_at': now(), 'source': 'local_linux_readonly',
            'board': {'model': aliases.get(normalized), 'reported_model': model,
                      'compatible': compatible.split('\x00') if compatible else [],
                      'architecture': arch, 'machine': machine, 'byteorder': byteorder,
                      'board_revision': None, 'identity_verified': False,
                      'airlink_version': os_fields.get('VERSION_ID') if os_fields.get('ID') == 'airlink' else None},
            'system': {'os': os_fields.get('PRETTY_NAME'), 'cpu': cpu_model,
                       'uptime_seconds': uptime, 'memory_total_bytes': mem_value('MemTotal'),
                       'memory_available_bytes': mem_value('MemAvailable')},
            'limitations': ['Board revision mapping is not implemented',
                            'Local reports do not establish physical-board compatibility',
                            'No flash, update, network configuration or PoE writes']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check-online', action='store_true')
    parser.add_argument('--watch', action='store_true', help='Report at startup and periodically until stopped')
    parser.add_argument('--interval', type=int, default=21600, help='Watch interval in seconds (300–86400)')
    args = parser.parse_args()
    if sys.platform != 'linux':
        parser.error('This probe requires Linux; RouterOS and macOS are not supported runtimes.')
    if not 300 <= args.interval <= 86400:
        parser.error('Interval must be 300–86400 seconds')
    client = CatalogClient()
    try:
        while True:
            report = collect()
            if args.check_online:
                report['update_check'] = client.check(report['board'])
            print(json.dumps(report), flush=True)
            if not args.watch:
                return
            time.sleep(args.interval)
    except KeyboardInterrupt:
        return


if __name__ == '__main__':
    main()
