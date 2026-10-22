#!/usr/bin/env python3
"""Exercise the real CPU popup with isolated preferences and a hidden AppKit window."""
from pathlib import Path
import argparse
import subprocess
import sys
import tempfile
import uuid

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--build-dir', type=Path, default=root / 'build')
args = parser.parse_args()
args.build_dir = args.build_dir.resolve()
source_root = root / 'stats-3.0.22' if (root / 'stats-3.0.22').exists() else root
source = source_root / 'Modules/CPU'
frameworks = args.build_dir / 'Stats Compact.app/Contents/Frameworks'
preflight = [sys.executable, str(root / 'check-local-app.py')]
subprocess.run([*preflight, str(frameworks.parents[1])], check=True)
with tempfile.TemporaryDirectory(prefix='stats-cpu-popup-') as temporary:
    directory = Path(temporary)
    combined = directory / 'popup-with-checks.swift'
    combined.write_text((source / 'popup.swift').read_text() + '\n' +
                        (Path(__file__).resolve().parent / 'cpu-popup-layout.swift').read_text())
    executable = directory / ('stats-cpu-popup-checks-' + uuid.uuid4().hex)
    command = [
        'xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library',
        '-O', '-whole-module-optimization', '-module-name', 'CPUPopupChecks',
        '-module-cache-path', '/tmp/stats-cpu-popup-module-cache',
        '-I', str(args.build_dir / 'modules'), '-F', str(frameworks), '-framework', 'Kit',
        '-import-objc-header', str(source / 'bridge.h'), '-lIOReport',
        '-Xlinker', '-rpath', '-Xlinker', str(frameworks),
        *[str(path) for path in sorted(source.glob('*.swift')) if path.name != 'popup.swift'],
        str(combined), '-o', str(executable)
    ]
    subprocess.run(command, check=True)
    subprocess.run([*preflight, str(executable)], check=True)
    subprocess.run([str(executable), str(source_root / 'Stats/Supporting Files/Assets.xcassets/devices')],
                   check=True, timeout=60)
