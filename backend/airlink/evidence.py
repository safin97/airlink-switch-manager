"""Collect read-only board evidence locally; does not boot, flash or configure."""
import argparse
import json
import os
from pathlib import Path

from .app import Settings
from .collector import CollectionError, SSHSession, utc

QUERIES = {
    'routerboard': '[/system routerboard print as-value]',
    'routerboot_settings': '[/system routerboard settings print as-value]',
    'resource': '[/system resource print as-value]',
    'ethernet': '[/interface ethernet print as-value]',
    'switch': '[/interface ethernet switch print as-value]',
    'health': '[/system health print as-value]',
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    settings = Settings.load()
    device = next((d for d in settings.devices if d.id == args.device), None)
    if device is None:
        parser.error('Device ID not configured')
    report = {'collected_at': utc(), 'expected_model': device.expected_model, 'evidence': {}}
    try:
        with SSHSession(device, os.environ) as session:
            for name, expression in QUERIES.items():
                try:
                    rows = session.query(expression)
                    for row in rows:
                        for key in list(row):
                            if any(word in key for word in ('serial-number', 'mac-address', 'comment', 'password')):
                                row[key] = '[redacted]'
                    report['evidence'][name] = rows
                except CollectionError as exc:
                    report['evidence'][name] = {'unavailable': str(exc)}
    except (CollectionError, OSError) as exc:
        parser.exit(1, 'Collection failed; check backend SSH configuration and connectivity.\n')
    destination = Path(args.output)
    # Exclusive creation avoids overwriting existing board evidence.
    fd = os.open(str(destination), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'w') as output:
        json.dump(report, output, indent=2)
        output.write('\n')
    print('Read-only evidence saved locally. Review before sharing.')


if __name__ == '__main__':
    main()
