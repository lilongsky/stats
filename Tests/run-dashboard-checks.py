#!/usr/bin/env python3
"""Compile the real Dashboard with synthetic display data and check its AppKit layout."""
from pathlib import Path
import argparse
import plistlib
import shutil
import subprocess
import sys
import tempfile
import uuid

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--build-dir', type=Path, default=root / 'build')
parser.add_argument('--output-dir', type=Path, required=True)
parser.add_argument('--locale', help='Helper-only AppleLocale, for example zh_CN')
parser.add_argument('--language', help='Helper-only AppleLanguages entry, for example zh-Hans')
args = parser.parse_args()
args.build_dir = args.build_dir.resolve()
args.output_dir = args.output_dir.resolve()
app = args.build_dir / 'Stats Compact.app'
frameworks = app / 'Contents/Frameworks'
preflight = [sys.executable, str(root / 'check-local-app.py')]
subprocess.run([*preflight, str(app)], check=True)

with tempfile.TemporaryDirectory(prefix='stats-dashboard-') as temporary:
    identifier = uuid.uuid4().hex
    helper = Path(temporary) / ('Dashboard Checks ' + identifier + '.app')
    resources = helper / 'Contents/Resources'
    executable = helper / 'Contents/MacOS' / ('stats-dashboard-checks-' + identifier)
    resources.mkdir(parents=True)
    executable.parent.mkdir(parents=True)
    with (helper / 'Contents/Info.plist').open('wb') as destination:
        plistlib.dump({
            'CFBundleIdentifier': 'local.stats.dashboard-checks.' + identifier,
            'CFBundleExecutable': executable.name,
            'CFBundleName': 'Isolated Dashboard Checks',
            'CFBundlePackageType': 'APPL',
            'CFBundleVersion': '1',
            'LSUIElement': True,
        }, destination)
    for language in (app / 'Contents/Resources').glob('*.lproj'):
        shutil.copytree(language, resources / language.name)
    # Compile the production view itself. The synthetic DisplayData initializer
    # neither creates SystemKit nor obtains an actual device serial number.
    subprocess.run([
        'xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library',
        '-O', '-whole-module-optimization', '-module-name', 'DashboardLayoutChecks',
        '-module-cache-path', '/tmp/stats-dashboard-module-cache',
        '-I', str(args.build_dir / 'modules'), '-F', str(frameworks), '-framework', 'Kit',
        '-Xlinker', '-rpath', '-Xlinker', str(frameworks),
        str(root / 'Stats/Views/Dashboard.swift'),
        str(Path(__file__).resolve().with_name('dashboard-layout.swift')),
        '-o', str(executable)
    ], check=True)
    subprocess.run(['/usr/bin/codesign', '--force', '--sign', '-', '--timestamp=none', str(helper)],
                   check=True)
    subprocess.run([*preflight, str(helper)], check=True)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    command = [str(executable), '--output-dir', str(args.output_dir)]
    if args.locale:
        command.extend(['-AppleLocale', args.locale])
    if args.language:
        command.extend(['-AppleLanguages', '(' + args.language + ')'])
    subprocess.run(command, check=True, timeout=60)
