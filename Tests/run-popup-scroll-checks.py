#!/usr/bin/env python3
"""Check nested scrolling in the real popup customization settings view."""
from pathlib import Path
import argparse
import plistlib
import subprocess
import sys
import tempfile
import uuid

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--build-dir', type=Path, default=root / 'build')
args = parser.parse_args()
build = args.build_dir.resolve()
app = build / 'Stats Compact.app'
frameworks = app / 'Contents/Frameworks'
preflight = [sys.executable, str(root / 'check-local-app.py')]
subprocess.run([*preflight, str(app)], check=True)

with tempfile.TemporaryDirectory(prefix='stats-popup-scroll-') as temporary:
    identifier = uuid.uuid4().hex
    helper = Path(temporary) / ('Popup Scroll Checks ' + identifier + '.app')
    executable = helper / 'Contents/MacOS' / ('stats-popup-scroll-checks-' + identifier)
    executable.parent.mkdir(parents=True)
    with (helper / 'Contents/Info.plist').open('wb') as destination:
        plistlib.dump({
            'CFBundleIdentifier': 'local.stats.popup-scroll-checks.' + identifier,
            'CFBundleExecutable': executable.name,
            'CFBundleName': 'Isolated Popup Scroll Checks',
            'CFBundlePackageType': 'APPL',
            'CFBundleVersion': '1',
            'LSUIElement': True,
        }, destination)
    subprocess.run([
        'xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library',
        '-O', '-whole-module-optimization', '-module-name', 'PopupScrollChecks',
        '-module-cache-path', '/tmp/stats-popup-scroll-module-cache',
        '-I', str(build / 'modules'), '-F', str(frameworks), '-framework', 'Kit',
        '-Xlinker', '-rpath', '-Xlinker', str(frameworks),
        str(Path(__file__).resolve().with_name('popup-scroll.swift')),
        '-o', str(executable)
    ], check=True)
    subprocess.run(['/usr/bin/codesign', '--force', '--sign', '-', '--timestamp=none', str(helper)],
                   check=True)
    subprocess.run([*preflight, str(helper)], check=True)
    subprocess.run([str(executable)], check=True, timeout=30)
