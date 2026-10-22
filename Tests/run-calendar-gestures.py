#!/usr/bin/env python3
"""Replay inertial delta curves and reversals against the production calendar."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source_root = root / 'stats-3.0.22' if (root / 'stats-3.0.22').exists() else root
source = source_root / 'Modules/Clock'
frameworks = root / 'build/Stats Compact.app/Contents/Frameworks'
with tempfile.TemporaryDirectory(prefix='stats-calendar-gestures-') as temporary:
    directory = Path(temporary)
    combined = directory / 'popup-with-gestures.swift'
    combined.write_text((source / 'popup.swift').read_text() + '\n' +
                        (root / 'Tests/calendar-gestures.swift').read_text())
    executable = directory / 'calendar-gestures'
    subprocess.run([
        'xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library',
        '-O', '-whole-module-optimization', '-module-name', 'ClockCalendarGestures',
        '-module-cache-path', '/tmp/stats-calendar-module-cache',
        '-I', str(root / 'build/modules'), '-F', str(frameworks), '-framework', 'Kit',
        '-Xlinker', '-rpath', '-Xlinker', str(frameworks),
        *[str(path) for path in sorted(source.glob('*.swift')) if path.name != 'popup.swift'],
        str(combined), '-o', str(executable)
    ], check=True)
    subprocess.run([str(executable)], check=True, timeout=30)
