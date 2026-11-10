"""Authenticated, HTTPS-only remote API. Run ONE worker: locks/cache are local."""
from __future__ import annotations

import copy
import hmac
import json
import os
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Literal, Optional

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, ConfigDict, Field, field_validator

from .collector import Collector, CollectionError, MODELS, UnsupportedDevice, utc
from .poe import ControlError, PoeControl
from .updates import CatalogClient, timestamp
from datetime import datetime, timezone


class Device(BaseModel):
    model_config = ConfigDict(extra="forbid")
    id: str = Field(pattern=r"^[a-zA-Z0-9_-]{1,64}$")
    label: str = Field(min_length=1, max_length=80)
    host: str = Field(min_length=1, max_length=253)
    port: int = Field(default=22, ge=1, le=65535)
    username: str = Field(min_length=1)
    expected_model: str
    known_hosts: str
    password_env: Optional[str] = None
    key_file: Optional[str] = None
    poe_control_ports: list[str] = Field(default_factory=list, max_length=16)
    control_username: Optional[str] = None
    control_password_env: Optional[str] = None
    control_key_file: Optional[str] = None

    @field_validator("poe_control_ports")
    @classmethod
    def valid_control_ports(cls, value):
        import re
        if len(set(value)) != len(value) or any(not re.fullmatch(r"ether(?:[1-9]|1[0-6])", p) for p in value):
            raise ValueError("PoE allowlist must contain unique copper default names")
        return value

    @field_validator("expected_model")
    @classmethod
    def supported_model(cls, value):
        if value not in MODELS:
            raise ValueError("expected_model must be an exact supported product code")
        return value


@dataclass
class Settings:
    token: str
    devices: list[Device]
    allow_loopback_http: bool = False
    origins: tuple = ()
    control_token: str = ""

    @classmethod
    def load(cls):
        token = os.environ.get("AIRLINK_API_TOKEN", "")
        if len(token) < 32:
            raise RuntimeError("AIRLINK_API_TOKEN must contain at least 32 characters")
        path = Path(os.environ.get("AIRLINK_CONFIG", "devices.json"))
        devices = [Device.model_validate(d) for d in json.loads(path.read_text())["devices"]]
        if len({d.id for d in devices}) != len(devices):
            raise RuntimeError("Duplicate device IDs")
        for d in devices:
            if not Path(d.known_hosts).is_file():
                raise RuntimeError("A verified known_hosts file is required for each device")
            if not d.key_file and not (d.password_env and os.environ.get(d.password_env)):
                raise RuntimeError("Backend-only SSH authentication is not configured")
            if d.poe_control_ports and (not d.control_username or not (
                    d.control_key_file or (d.control_password_env and os.environ.get(d.control_password_env)))):
                raise RuntimeError("PoE control requires separate backend SSH credentials")
        return cls(token, devices, os.environ.get("AIRLINK_ALLOW_LOOPBACK_HTTP") == "1",
                   tuple(x.strip() for x in os.environ.get("AIRLINK_CORS_ORIGINS", "").split(",") if x.strip()),
                   os.environ.get("AIRLINK_CONTROL_TOKEN", ""))


class PoePrepare(BaseModel):
    model_config = ConfigDict(extra="forbid")
    default_name: str = Field(pattern=r"^ether[1-9][0-9]*$", max_length=16)
    expected_name: str = Field(min_length=1, max_length=255)
    mode: Literal["auto-on", "off"]


class PoeCommit(BaseModel):
    model_config = ConfigDict(extra="forbid")
    confirmation_id: str = Field(min_length=32, max_length=100)
    confirmed: bool = Field(strict=True)


class DeviceMonitor:
    def __init__(self, collector):
        self.collector = collector
        self.lock = threading.Lock()
        self.cached = None
        self.next_attempt = 0.0
        self.failure = None
        self.failures = 0

    def snapshot(self):
        if not self.lock.acquire(blocking=False):
            if self.cached:
                data = copy.deepcopy(self.cached)
                data.update(stale=True, status="refreshing", served_at=utc())
                return data
            raise HTTPException(503, "Collection in progress; retry shortly", headers={"Retry-After": "2"})
        try:
            if time.monotonic() < self.next_attempt:
                if self.cached:
                    return copy.deepcopy(self.cached)
                raise HTTPException(self.failure[0], self.failure[1])
            try:
                data = self.collector.collect()
                self.cached, self.failure, self.failures = data, None, 0
                self.next_attempt = time.monotonic() + 2
            except (CollectionError, OSError) as exc:
                self.failures += 1
                self.next_attempt = time.monotonic() + min(30, 2 ** min(self.failures, 5))
                code = str(exc) if isinstance(exc, CollectionError) else "backend_ssh_configuration_error"
                status = 422 if isinstance(exc, UnsupportedDevice) else 503
                self.failure = (status, code)
                if status == 422:
                    # Never show cached data for a replacement/mismatched device.
                    self.cached = None
                if not self.cached:
                    raise HTTPException(status, code) from None
                self.cached = copy.deepcopy(self.cached)
                self.cached.update(stale=True, status="disconnected", error=code, served_at=utc())
            return copy.deepcopy(self.cached)
        finally:
            self.lock.release()


def create_app(settings: Settings | None = None, collector_factory=Collector, control_factory=PoeControl, catalog_client=None):
    settings = settings or Settings.load()
    if len(settings.token) < 32:
        raise RuntimeError("API token too short")
    if settings.control_token and (len(settings.control_token) < 32 or settings.control_token == settings.token):
        raise RuntimeError("Control token must be distinct from monitoring and at least 32 characters")
    for d in settings.devices:
        if d.poe_control_ports and (not settings.control_token or not d.control_username or d.control_username == d.username):
            raise RuntimeError("PoE control requires an operator token and separate SSH username")
        if any(int(p[5:]) > MODELS[d.expected_model]['ethernet'] for p in d.poe_control_ports):
            raise RuntimeError("PoE allowlist exceeds the model's copper ports")
    app = FastAPI(title="AirLink monitoring and explicit PoE control", docs_url=None, redoc_url=None, openapi_url=None)
    if settings.origins:
        app.add_middleware(CORSMiddleware, allow_origins=list(settings.origins),
                           allow_methods=["GET", "POST"], allow_headers=["Authorization", "Content-Type"])
    monitors = {d.id: DeviceMonitor(collector_factory(d, os.environ)) for d in settings.devices}
    controls = {d.id: control_factory(d, os.environ) for d in settings.devices if d.poe_control_ports}
    profiles = {d.id: d for d in settings.devices}
    catalog = catalog_client or CatalogClient()

    @app.middleware("http")
    async def transport_security(request: Request, call_next):
        loopback = request.client is not None and request.client.host in ("127.0.0.1", "::1", "testclient")
        if request.url.scheme != "https" and not (settings.allow_loopback_http and loopback):
            from fastapi.responses import JSONResponse
            return JSONResponse(status_code=400, content={"detail": "HTTPS required"})
        response = await call_next(request)
        response.headers["Cache-Control"] = "no-store"
        response.headers["X-Content-Type-Options"] = "nosniff"
        return response

    def authenticate(request: Request):
        provided = request.headers.get("Authorization", "")
        if not hmac.compare_digest(provided.encode(), ("Bearer " + settings.token).encode()):
            raise HTTPException(401, "Authentication required", headers={"WWW-Authenticate": "Bearer"})

    def authorize_control(request: Request):
        provided = request.headers.get("Authorization", "")
        if not settings.control_token or not hmac.compare_digest(
                provided.encode(), ("Bearer " + settings.control_token).encode()):
            raise HTTPException(403, "Separate PoE operator token required")

    def run_control(device_id, operation, invalidate=False):
        if device_id not in monitors:
            raise HTTPException(404, "Unknown device profile")
        if device_id not in controls:
            raise HTTPException(403, "PoE control disabled for this device")
        monitor = monitors[device_id]
        if not monitor.lock.acquire(blocking=False):
            raise HTTPException(409, "Device busy; wait for monitoring or control to finish")
        try:
            if invalidate:
                monitor.next_attempt = 0
                if monitor.cached:
                    monitor.cached = copy.deepcopy(monitor.cached)
                    monitor.cached.update(stale=True, status="refreshing", served_at=utc())
            return operation(controls[device_id])
        except ControlError as exc:
            raise HTTPException(exc.status, exc.code) from None
        except UnsupportedDevice:
            monitor.cached = None
            raise HTTPException(422, "unsupported_or_mismatched_device") from None
        except (CollectionError, OSError):
            raise HTTPException(503, "poe_preflight_unavailable_no_write_sent") from None
        finally:
            monitor.lock.release()

    @app.post("/api/v1/devices/{device_id}/poe/prepare", dependencies=[Depends(authorize_control)])
    def prepare_poe(device_id: str, action: PoePrepare):
        return run_control(device_id, lambda ctl: ctl.prepare(action.default_name, action.expected_name, action.mode))

    @app.post("/api/v1/devices/{device_id}/poe/commit", dependencies=[Depends(authorize_control)])
    def commit_poe(device_id: str, action: PoeCommit):
        if not action.confirmed:
            raise HTTPException(400, "Explicit confirmation required")
        return run_control(device_id, lambda ctl: ctl.commit(action.confirmation_id), invalidate=True)

    @app.get("/api/v1/devices", dependencies=[Depends(authenticate)])
    def devices():
        return {"devices": [{"id": d.id, "label": d.label, "expected_model": d.expected_model} for d in settings.devices]}

    @app.get("/api/v1/devices/{device_id}/snapshot", dependencies=[Depends(authenticate)])
    def snapshot(device_id: str):
        if device_id not in monitors:
            raise HTTPException(404, "Unknown device profile")
        data = monitors[device_id].snapshot()
        data['controls'] = {'poe_ports': profiles[device_id].poe_control_ports,
                            'operator_token_required': True}
        return data

    @app.get('/api/v1/devices/{device_id}/firmware/check', dependencies=[Depends(authenticate)])
    def check_firmware(device_id: str):
        if device_id not in monitors:
            raise HTTPException(404, 'Unknown device profile')
        data = monitors[device_id].snapshot()
        try:
            age = (datetime.now(timezone.utc) - timestamp(data.get('last_success_at'))).total_seconds()
        except (ValueError, TypeError):
            age = 9999
        if data.get('stale') or not -5 <= age <= 60 or data.get('device', {}).get('verified') is not True:
            raise HTTPException(409, 'Fresh verified board readings required')
        device = data['device']
        board = {k: device.get(k) for k in ['model', 'architecture', 'board_revision']}
        board.update(source='routeros_verified_ssh', observed_at=data['last_success_at'],
                     routeros_version=data.get('system', {}).get('routeros_version'), airlink_version=None)
        return dict(catalog.check(board), device_id=device_id, mode='live')

    return app
