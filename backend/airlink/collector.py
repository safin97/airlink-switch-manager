"""RouterOS v6/v7 SSH collector. No REST dependency or configuration writes.

Framed, percent-escaped scalar fields avoid human CLI tables, terminal wrapping,
semicolon arrays and JSON serialization only available in newer RouterOS.
Scripts are built from constants and validated internal interface IDs only.
"""
from __future__ import annotations

import re
import socket
import time
from datetime import datetime, timezone
from typing import Any

import paramiko

MODELS = {
    "CRS318-16P-2S+OUT": {"ethernet": 16, "fiber": 2, "fiber_type": "SFP+",
                         "aliases": {"CRS318-16P-2S+OUT", "CRS318-16P-2S+"}},
    "CRS112-8P-4S-IN": {"ethernet": 8, "fiber": 4, "fiber_type": "SFP",
                       "aliases": {"CRS112-8P-4S-IN", "CRS112-8P-4S"}},
}


class CollectionError(Exception):
    """Public, sanitized failure code, never raw SSH output or credentials."""


class UnsupportedDevice(CollectionError):
    pass


def utc() -> str:
    return datetime.now(timezone.utc).isoformat()


# All fields come from read-only menus. Nested array fields are intentionally
# excluded; no logs, passwords, exports or configurations are requested.
EMITTER = r''':local emit do={
 :put "ALREC";
 :foreach k,v in=$row do={
  :if ([:typeof $v] != "array") do={
   :local s [:tostr $v]; :local out "";
   :if ([:len $s] > 0) do={ :for i from=0 to=([:len $s]-1) do={
    :local c [:pick $s $i ($i+1)];
    :if ($c = "%") do={ :set c "%25" } else={
     :if ($c = "\n") do={ :set c "%0A" } else={
      :if ($c = "\r") do={ :set c "%0D" } else={
       :if ($c = "\t") do={ :set c "%09" }
      }
     }
    };
    :set out ($out . $c);
   } };
   :put ("AL1\t" . $k . "\t" . $out);
  }
 };
 :put "ALENDREC";
};'''


def script(expression: str) -> str:
    # print as-value may return a map (resource) or an array of maps (interfaces).
    return EMITTER + r'''
:put "ALBEGIN";
:local rows ''' + expression + r''';
:local nested ([:typeof ($rows->0)] = "array");
:if ($nested) do={ :foreach row in=$rows do={ $emit row=$row } } else={ $emit row=$rows };
:put "ALDONE";'''


EXPRESSIONS = {
    "resource": "[/system resource print as-value]",
    "board": "[/system routerboard print as-value]",
    "identity": "[/system identity print as-value]",
    "ethernet": "[/interface ethernet print as-value]",
    "counters": "[/interface print stats as-value]",
    "health": "[/system health print as-value]",
}


def parse_frames(output: str) -> list[dict[str, str]]:
    lines = output.replace("\r\n", "\n").splitlines()
    # An end marker is mandatory: a truncated response must not become fresh data.
    if not lines or lines[0] != "ALBEGIN" or lines[-1] != "ALDONE":
        raise CollectionError("unsupported_command_or_incomplete_response")
    rows, row = [], None
    for line in lines[1:-1]:
        if line == "ALREC" and row is None:
            row = {}
        elif line == "ALENDREC" and row is not None:
            rows.append(row)
            row = None
        elif line.startswith("AL1\t") and row is not None:
            parts = line.split("\t", 2)
            if len(parts) != 3 or not re.fullmatch(r"[.a-zA-Z0-9_-]+", parts[1]) or parts[1] in row:
                raise CollectionError("malformed_response")
            # Decode ONLY our four escapes, in one pass, preserving literal %0A.
            row[parts[1]] = re.sub(r"%(25|0A|0D|09)",
                                 lambda m: {"25": "%", "0A": "\n", "0D": "\r", "09": "\t"}[m[1]], parts[2])
        else:
            raise CollectionError("malformed_response")
    if row is not None:
        raise CollectionError("incomplete_record")
    return rows


def number(value: Any, unit: str = "") -> float | None:
    if value is None:
        return None
    match = re.fullmatch(r"\s*(-?\d+(?:\.\d+)?)\s*([A-Za-z°%/]+)?\s*", str(value))
    if not match:
        return None
    n, suffix = float(match[1]), match[2] or ""
    factors = {
        "": {"": 1, "%": 1}, "V": {"V": 1, "mV": .001},
        "A": {"": .001, "A": 1, "mA": .001}, "W": {"W": 1, "mW": .001},
        "C": {"": 1, "C": 1, "°C": 1},
        "Mbps": {"bps": .000001, "kbps": .001, "Mbps": 1, "Gbps": 1000},
        "bytes": {"": 1, "B": 1, "KiB": 1024, "MiB": 1048576, "GiB": 1073741824},
    }
    factor = factors.get(unit, {}).get(suffix)
    return n * factor if factor is not None else None


def counter(value: Any) -> int | None:
    # Never pass uint64 counters through float (loses precision above 2**53).
    return int(str(value)) if value is not None and re.fullmatch(r"\d+", str(value)) else None


def boolean(value: Any) -> bool | None:
    return {"true": True, "yes": True, "false": False, "no": False}.get(str(value).lower())


def uptime_seconds(value: str) -> float | None:
    if re.fullmatch(r"(?:\d+w)?(?:\d+d)?(?:\d+h)?(?:\d+m)?(?:\d+(?:\.\d+)?s)?", value) and value:
        return sum(float(n) * {"w": 604800, "d": 86400, "h": 3600, "m": 60, "s": 1}[u]
                   for n, u in re.findall(r"(\d+(?:\.\d+)?)([wdhms])", value))
    m = re.fullmatch(r"(?:(\d+)w)?(?:(\d+)d)?(\d+):(\d+):(\d+(?:\.\d+)?)", value)
    return sum(float(n or 0) * f for n, f in zip(m.groups(), [604800, 86400, 3600, 60, 1])) if m else None


class RateTracker:
    def __init__(self):
        self.previous = {}
        self.uptime = None

    def update(self, ports: list[dict], now: float, uptime: float | None) -> None:
        reboot = uptime is not None and self.uptime is not None and uptime < self.uptime
        current = {}
        for p in ports:
            key = (p["id"], p["default_name"])
            old = None if reboot else self.previous.get(key)
            p["counter_reset"] = reboot
            for direction in ("rx", "tx"):
                value = p[f"{direction}_bytes"]
                p[f"{direction}_mbps"] = None
                if old and value is not None and old[direction] is not None and now > old["time"]:
                    delta = value - old[direction]
                    if delta >= 0:
                        p[f"{direction}_mbps"] = delta * 8 / (now - old["time"]) / 1_000_000
                    else:
                        p["counter_reset"] = True
                current.setdefault(key, {"time": now})[direction] = value
        self.previous, self.uptime = current, uptime


class SSHSession:
    def __init__(self, device, environ):
        self.device, self.environ = device, environ
        self.client = paramiko.SSHClient()
        try:
            self.client.load_host_keys(device.known_hosts)
        except (OSError, paramiko.SSHException):
            raise CollectionError("invalid_trusted_host_key_file") from None
        self.client.set_missing_host_key_policy(paramiko.RejectPolicy())
        self.deadline = 0.0

    def __enter__(self):
        d = self.device
        try:
            self.client.connect(d.host, port=d.port, username=d.username,
                                password=self.environ.get(d.password_env) if d.password_env else None,
                                key_filename=d.key_file, timeout=6, auth_timeout=6, banner_timeout=6,
                                allow_agent=False, look_for_keys=False)
            self.deadline = time.monotonic() + 45
            return self
        except paramiko.BadHostKeyException:
            self.client.close()
            raise CollectionError("host_key_mismatch") from None
        except paramiko.AuthenticationException:
            self.client.close()
            raise CollectionError("router_authentication_failed") from None
        except (paramiko.SSHException, OSError):
            self.client.close()
            raise CollectionError("ssh_connection_failed_check_trusted_host_key") from None

    def __exit__(self, *args):
        self.client.close()

    def query(self, expression):
        return self.execute(script(expression))

    def execute(self, command):
        """Internal framed command transport; never accepts HTTP-supplied scripts."""
        remaining = self.deadline - time.monotonic()
        if remaining <= 0:
            raise CollectionError("collection_timeout")
        channel = None
        try:
            transport = self.client.get_transport()
            if transport is None or not transport.is_active():
                raise CollectionError("ssh_disconnected")
            channel = transport.open_session(timeout=min(6, remaining))
            channel.settimeout(min(6, remaining))
            channel.exec_command(command)
            end = min(self.deadline, time.monotonic() + 6)
            output, errors = bytearray(), bytearray()
            while True:
                if time.monotonic() >= end:
                    raise CollectionError("command_timeout")
                if channel.recv_ready():
                    output.extend(channel.recv(65536))
                if channel.recv_stderr_ready():
                    errors.extend(channel.recv_stderr(4096))
                if len(output) > 1_000_000 or len(errors) > 8192:
                    raise CollectionError("response_too_large")
                if channel.exit_status_ready() and not channel.recv_ready() and not channel.recv_stderr_ready():
                    break
                time.sleep(.005)
            if errors or channel.recv_exit_status() != 0:
                raise CollectionError("unsupported_command_or_permission_denied")
            return [row for row in parse_frames(output.decode("utf-8", errors="strict").strip()) if row]
        except (socket.timeout, OSError, paramiko.SSHException, UnicodeError):
            raise CollectionError("ssh_command_failed") from None
        finally:
            if channel is not None:
                channel.close()


def detect_model(board: dict, resource: dict, expected: str) -> str:
    reported = board.get("model", "")
    actual = next((model for model, spec in MODELS.items() if reported in spec["aliases"]), None)
    if actual is None or (expected and actual != expected):
        raise UnsupportedDevice("unsupported_or_mismatched_model")
    arch = resource.get("architecture-name")
    if arch != ("arm" if actual.startswith("CRS318") else "mipsbe"):
        raise UnsupportedDevice("unsupported_or_mismatched_architecture")
    return actual


def validate_ports(rows: list[dict], model: str) -> list[dict]:
    spec = MODELS[model]
    copper = [r for r in rows if re.fullmatch(r"ether\d+", r.get("default-name", ""))]
    fiber = [r for r in rows if re.fullmatch(r"sfp(?:-sfpplus)?\d+", r.get("default-name", ""))]
    if (len(copper) != spec["ethernet"] or len(fiber) != spec["fiber"]
            or len(rows) != len(copper) + len(fiber)
            or {r["default-name"] for r in copper} != {f"ether{i}" for i in range(1, spec["ethernet"] + 1)}
            or len({r.get(".id") for r in rows}) != len(rows)
            or len({r.get("name") for r in rows}) != len(rows)
            or len({r.get("default-name") for r in rows}) != len(rows)
            or any(not r.get("name") or not re.fullmatch(r"\*[0-9A-Fa-f]+", r.get(".id", "")) for r in rows)):
        raise UnsupportedDevice("physical_port_inventory_unverified")
    # Retain discovered fiber default names (including hardware using sfp9..12).
    return sorted(copper, key=lambda r: int(re.search(r"\d+$", r["default-name"])[0])) + sorted(
        fiber, key=lambda r: int(re.search(r"\d+$", r["default-name"])[0]))


class Collector:
    def __init__(self, device, environ, session_factory=SSHSession):
        self.device, self.environ, self.session_factory = device, environ, session_factory
        self.rates = RateTracker()

    def collect(self):
        warnings = []
        with self.session_factory(self.device, self.environ) as session:
            def query(key, optional=False, expression=None):
                try:
                    return session.query(expression or EXPRESSIONS[key])
                except CollectionError as exc:
                    if not optional:
                        raise
                    warnings.append({"section": key, "code": str(exc)})
                    return []

            resource_rows, board_rows = query("resource"), query("board")
            if len(resource_rows) != 1 or len(board_rows) != 1:
                raise CollectionError("identity_response_incomplete")
            resource, board = resource_rows[0], board_rows[0]
            resource_at = utc()
            model = detect_model(board, resource, self.device.expected_model)
            physical = validate_ports(query("ethernet"), model)
            counter_rows = query("counters", optional=True)
            counter_at, counter_clock = utc(), time.monotonic()
            counters = {r["name"]: r for r in counter_rows if "name" in r}
            identity = query("identity", optional=True)
            health = query("health", optional=True)
            health_at = utc()
            ports = []
            for r in physical:
                internal_id = r[".id"]  # regex validated, never interpolate a user name
                mon = query(r["default-name"] + ".link", True,
                            f"[/interface ethernet monitor {internal_id} once as-value]")
                link_at = utc() if mon else None
                m = mon[0] if len(mon) == 1 else {}
                is_copper = r["default-name"].startswith("ether")
                poe = query(r["default-name"] + ".poe", True,
                            f"[/interface ethernet poe monitor [/interface ethernet get {internal_id} name] once as-value]") if is_copper else []
                p = poe[0] if len(poe) == 1 else {}
                c = counters.get(r["name"], {})
                disabled = boolean(r.get("disabled"))
                ports.append({
                    "id": internal_id, "name": r["name"], "default_name": r["default-name"],
                    "kind": "Ethernet" if is_copper else MODELS[model]["fiber_type"],
                    "enabled": None if disabled is None else not disabled,
                    "link": m.get("status"), "speed_mbps": number(m.get("rate"), "Mbps"),
                    "full_duplex": boolean(m.get("full-duplex")),
                    "rx_bytes": counter(c.get("rx-byte")), "tx_bytes": counter(c.get("tx-byte")),
                    "observed_at": link_at, "counters_at": counter_at if c else None,
                    "poe": {"status": p.get("poe-out-status"),
                            "configuration_mode": r.get("poe-out"),
                            "voltage_v": number(p.get("poe-out-voltage"), "V"),
                            "current_a": number(p.get("poe-out-current"), "A"),
                            "power_w": number(p.get("poe-out-power"), "W"),
                            "observed_at": utc() if p else None},
                })
            temperatures = []
            for h in health:
                if "temperature" in h.get("name", ""):
                    temperatures.append({"name": h["name"], "celsius": number(h.get("value"), "C")})
                else:
                    for k, v in h.items():
                        if "temperature" in k:
                            temperatures.append({"name": k, "celsius": number(v, "C")})
            self.rates.update(ports, counter_clock, uptime_seconds(resource.get("uptime", "")))
            for port in ports:
                for key in ("rx_bytes", "tx_bytes"):
                    if port[key] is not None:
                        port[key] = str(port[key])
            return {
                "schema_version": 1, "mode": "live", "device_id": self.device.id,
                "status": "partial" if warnings else "connected", "stale": False,
                "last_success_at": utc(), "collected_at": utc(),
                "units": {"traffic_rate": "Mbps", "counters": "bytes", "voltage": "V",
                          "current": "A", "power": "W", "temperature": "C", "memory": "bytes", "cpu": "%"},
                "device": {"model": model, "reported_model": board.get("model"),
                           "board_revision": board.get("revision"),
                           "identity": identity[0].get("name") if identity else None,
                           "architecture": resource.get("architecture-name"), "verified": True},
                "system": {"cpu_percent": number(resource.get("cpu-load")),
                           "free_memory_bytes": number(resource.get("free-memory"), "bytes"),
                           "total_memory_bytes": number(resource.get("total-memory"), "bytes"),
                           "uptime": resource.get("uptime"), "routeros_version": resource.get("version"),
                           "temperatures": temperatures, "observed_at": resource_at,
                           "health_at": health_at if health else None},
                "ports": ports, "warnings": warnings,
            }
