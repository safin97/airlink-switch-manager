#!/usr/bin/env python3
"""Exercise the staged probe in generic Linux, never switch hardware."""
from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
IMAGE = 'airlink-switch-probe-integration:test'


def run(arguments, online=False, entrypoint=None):
    command = ['docker', 'run', '--rm', '--platform', 'linux/amd64', '--read-only',
               '--network', 'bridge' if online else 'none', '--cap-drop', 'ALL',
               '--security-opt', 'no-new-privileges']
    if entrypoint:
        command += ['--entrypoint', entrypoint]
    if entrypoint == '/usr/bin/systemd-analyze':
        # The amd64 runtime/unit checker needs temporary files. This is a private
        # RAM filesystem inside this one test container, never a host mount.
        command += ['--tmpfs', '/tmp:rw,nosuid,nodev,size=16m,mode=1777']
    command += [IMAGE, *arguments]
    return subprocess.run(command, text=True, capture_output=True, timeout=45, check=True).stdout


def main():
    local = json.loads(run([]))
    assert local['source'] == 'local_linux_readonly'
    assert local['board']['model'] is None and local['board']['board_revision'] is None
    assert local['board']['identity_verified'] is False
    assert local['board']['airlink_version'] is None
    assert local['system']['memory_total_bytes'] > 0 and local['system']['uptime_seconds'] >= 0

    offline = json.loads(run(['--check-online']))['update_check']
    assert offline['status'] == 'catalog_unavailable' and offline['stale'] is True
    assert offline['last_success_at'] is None and offline['candidate'] is None

    online = json.loads(run(['--check-online'], online=True))['update_check']
    assert online['status'] == 'no_published_firmware' and online['stale'] is False
    assert online['last_success_at'] is not None and online['installation_allowed'] is False

    run(['verify', '/usr/lib/systemd/system/airlink-board-probe.service'], entrypoint='/usr/bin/systemd-analyze')
    watch = """
import json,os,select,signal,subprocess,sys
assert os.getuid() == 65534
p=subprocess.Popen([sys.executable,'-I','/usr/lib/airlink-board-probe/launcher.py',
                    '--watch','--interval','300'],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
try:
    assert select.select([p.stdout],[],[],10)[0], 'No startup report'
    data=json.loads(p.stdout.readline())
    assert data['board']['identity_verified'] is False
    p.send_signal(signal.SIGINT)
    tail,errors=p.communicate(timeout=10)
    assert p.returncode == 0 and not tail and not errors
    print(json.dumps({'uid':os.getuid(),'startup_report':True,'sigint_exit_code':p.returncode}))
finally:
    if p.poll() is None:
        p.kill();p.wait()
"""
    watched = json.loads(run(['-I', '-c', watch], entrypoint='/usr/bin/python3'))
    image_id = subprocess.check_output(['docker', 'image', 'inspect', IMAGE, '--format', '{{.Id}}'], text=True).strip()
    versions = json.loads(run(['-I', '-c', 'import json,platform,sys; print(json.dumps({"python":sys.version.split()[0],"machine":platform.machine()}))'], entrypoint='/usr/bin/python3'))
    report = {'checked_at': datetime.now(timezone.utc).isoformat(),
              'scope': 'Generic Debian amd64 Linux container under emulation on ARM64 Docker Desktop; not MikroTik hardware',
              'image_id': image_id, 'runtime': versions,
              'read_only_root': True, 'unprivileged_uid': watched['uid'], 'capabilities': [],
              'checks': {'local_linux_reads': True, 'unknown_board_not_fabricated': True,
                         'offline_catalog_failure': True, 'actual_https_catalog': True,
                         'systemd_unit_validation': True, 'watch_startup_and_sigint': True},
              'systemd_boot_activation_tested': False, 'switch_hardware_verified': False,
              'ram_boot_verified': False, 'installable_firmware': False}
    output = ROOT / 'firmware/integration/linux/validation.json'
    output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
