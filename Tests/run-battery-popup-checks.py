#!/usr/bin/env python3
"""Check the production Battery popup in an isolated, hidden AppKit probe."""
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
parser.add_argument('--language', nargs='+', choices=['en', 'zh-Hans'], default=['zh-Hans'])
parser.add_argument('--output-dir', type=Path)
args = parser.parse_args()
build = args.build_dir.resolve()
source_root = root / 'stats-3.0.22' if (root / 'stats-3.0.22').exists() else root
source = source_root / 'Modules/Battery'
frameworks = build / 'Stats Compact.app/Contents/Frameworks'
preflight = [sys.executable, str(root / 'check-local-app.py')]
subprocess.run([*preflight, str(frameworks.parents[1])], check=True)
with tempfile.TemporaryDirectory(prefix='stats-battery-popup-') as temporary:
    directory = Path(temporary)
    app = directory / 'Battery Popup Probe.app'
    executable_name = 'stats-battery-popup-checks-' + uuid.uuid4().hex
    identifier = 'local.statscompact.battery-popup-checks.' + uuid.uuid4().hex
    executable = app / 'Contents/MacOS' / executable_name
    executable.parent.mkdir(parents=True)
    resources = app / 'Contents/Resources'
    resources.mkdir()
    (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
        'CFBundleIdentifier': identifier,
        'CFBundleExecutable': executable_name,
        'CFBundleName': 'Battery Popup Probe',
        'CFBundlePackageType': 'APPL',
        'CFBundleVersion': '1',
        'LSUIElement': True,
    }))
    for language in ['en', 'zh-Hans', 'zh-Hant']:
        destination = resources / (language + '.lproj')
        destination.mkdir()
        shutil.copy2(source_root / 'Stats/Supporting Files' / (language + '.lproj/Localizable.strings'),
                     destination / 'Localizable.strings')
    # Compile the real value records and popup, without the module initializer,
    # telemetry readers, application delegate or notification services.
    models = (source / 'main.swift').read_text().split('public class Battery: Module', 1)
    if len(models) != 2:
        raise SystemExit('Battery model boundary changed; inspect before running the probe.')
    combined = directory / 'battery-popup-with-checks.swift'
    combined.write_text(models[0] + '\n' + (source / 'popup.swift').read_text() + '\n' +
                        (Path(__file__).parent / 'battery-popup-layout.swift').read_text())
    subprocess.run([
        'xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library',
        '-O', '-whole-module-optimization', '-module-name', 'BatteryPopupChecks',
        '-module-cache-path', str(directory / 'module-cache'),
        '-I', str(build / 'modules'), '-F', str(frameworks), '-framework', 'Kit',
        '-Xlinker', '-rpath', '-Xlinker', str(frameworks),
        str(combined), '-o', str(executable),
    ], check=True)
    subprocess.run(['codesign', '--force', '--deep', '--sign', '-', str(app)], check=True)
    subprocess.run([*preflight, str(app)], check=True)
    output = str(args.output_dir.resolve()) if args.output_dir else ''
    for language in args.language:
        subprocess.run([
            str(executable),
            str(source_root / 'Stats/Supporting Files/Assets.xcassets/devices'),
            output, language,
        ], check=True, timeout=60)
