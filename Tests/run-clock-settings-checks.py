#!/usr/bin/env python3
"""Exercise the real Clock settings with synthetic records in an isolated helper."""
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
build = args.build_dir.resolve()
app = build / 'Stats Compact.app'
frameworks = app / 'Contents/Frameworks'
preflight = [sys.executable, str(root / 'check-local-app.py')]
subprocess.run([*preflight, str(app)], check=True)

with tempfile.TemporaryDirectory(prefix='stats-clock-settings-') as temporary:
    identifier = uuid.uuid4().hex
    helper = Path(temporary) / ('Clock Settings Checks ' + identifier + '.app')
    resources = helper / 'Contents/Resources'
    executable = helper / 'Contents/MacOS' / ('stats-clock-settings-checks-' + identifier)
    resources.mkdir(parents=True)
    executable.parent.mkdir(parents=True)
    with (helper / 'Contents/Info.plist').open('wb') as destination:
        plistlib.dump({
            'CFBundleIdentifier': 'local.stats.clock-settings-checks.' + identifier,
            'CFBundleExecutable': executable.name,
            'CFBundleName': 'Isolated Clock Settings Checks',
            'CFBundlePackageType': 'APPL',
            'CFBundleVersion': '1',
            'LSUIElement': True,
        }, destination)
    for language in (app / 'Contents/Resources').glob('*.lproj'):
        shutil.copytree(language, resources / language.name)
    # Compile the actual Settings and Clock model/menu implementations. Neither
    # Clock module nor its reader is instantiated, so no NTP operation is started.
    subprocess.run([
        'xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library',
        '-Onone', '-module-name', 'ClockSettingsLayoutChecks',
        '-module-cache-path', '/tmp/stats-clock-settings-module-cache',
        '-I', str(build / 'modules'), '-F', str(frameworks), '-framework', 'Kit',
        '-Xlinker', '-rpath', '-Xlinker', str(frameworks),
        *map(str, sorted((root / 'Modules/Clock').glob('*.swift'))),
        str(Path(__file__).resolve().with_name('clock-settings-layout.swift')),
        '-o', str(executable)
    ], check=True)
    subprocess.run(['/usr/bin/codesign', '--force', '--sign', '-', '--timestamp=none', str(helper)], check=True)
    subprocess.run([*preflight, str(helper)], check=True)
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    command = [str(executable), '--output-dir', str(output)]
    if args.locale:
        command.extend(['-AppleLocale', args.locale])
    if args.language:
        command.extend(['-AppleLanguages', '(' + args.language + ')'])
    subprocess.run(command, check=True, timeout=60)
