#!/usr/bin/env python3
"""Check timing, fan-curve interpolation and history storage without hardware changes."""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
source = root / 'stats-3.0.22' if (root / 'stats-3.0.22').exists() else root
preflight = [sys.executable, str(root / 'check-local-app.py')]
with tempfile.TemporaryDirectory(prefix='stats-feature-models-') as temporary:
    executable = Path(temporary) / 'feature-models'
    subprocess.run([
        'xcrun', 'swiftc', '-O', '-parse-as-library',
        '-module-cache-path', '/tmp/stats-calendar-module-cache',
        str(source / 'Kit/Local/LocalModels.swift'),
        str(source / 'Kit/Local/HistoryArchive.swift'),
        str(root / 'Tests/local-feature-models.swift'), '-lsqlite3', '-o', str(executable)
    ], check=True)
    subprocess.run([*preflight, str(executable)], check=True)
    subprocess.run([str(executable)], check=True, timeout=30)
