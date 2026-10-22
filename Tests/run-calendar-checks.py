#!/usr/bin/env python3
"""Compile the real Clock sources with the private calendar integration checks."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source_root = root / 'stats-3.0.22' if (root / 'stats-3.0.22').exists() else root
source = source_root / 'Modules/Clock'
frameworks = root / 'build/Stats Compact.app/Contents/Frameworks'
with tempfile.TemporaryDirectory(prefix='stats-calendar-checks-') as temporary:
    directory = Path(temporary)
    combined = directory / 'popup-with-checks.swift'
    combined.write_text((source / 'popup.swift').read_text() + '\n' +
                        (root / 'Tests/calendar-scroll.swift').read_text())
    executable = directory / 'calendar-checks'
    command = [
        'xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library',
        '-O', '-whole-module-optimization',
        '-module-name', 'ClockCalendarChecks',
        '-module-cache-path', '/tmp/stats-calendar-module-cache',
        '-I', str(root / 'build/modules'), '-F', str(frameworks), '-framework', 'Kit',
        '-Xlinker', '-rpath', '-Xlinker', str(frameworks),
        *[str(path) for path in sorted(source.glob('*.swift')) if path.name != 'popup.swift'],
        str(combined), '-o', str(executable)
    ]
    subprocess.run(command, check=True)
    subprocess.run([str(executable)], check=True)
