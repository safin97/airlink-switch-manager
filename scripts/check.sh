#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
dart format --output=none --set-exit-if-changed lib test integration_test test_driver
flutter analyze
flutter test
PYTHONPATH=backend backend/.venv/bin/python -m pytest backend/tests -q
