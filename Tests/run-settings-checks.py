#!/usr/bin/env python3
"""Check production settings views in isolation and save private offscreen previews."""
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
parser.add_argument('--output-dir', type=Path,
                    help='Private PNG directory (default: BUILD/settings-evidence)')
parser.add_argument('--locale', help='Helper-only AppleLocale, for example zh_CN')
parser.add_argument('--language', help='Helper-only AppleLanguages entry, for example zh-Hans')
parser.add_argument('--render-only', action='store_true',
                    help='Render the same fixture with an older matching Kit; skip layout/action checks')
args = parser.parse_args()
args.build_dir = args.build_dir.resolve()
args.output_dir = (args.output_dir or args.build_dir / 'settings-evidence').resolve()
frameworks = args.build_dir / 'Stats Compact.app/Contents/Frameworks'
preflight = [sys.executable, str(root / 'check-local-app.py')]
subprocess.run([*preflight, str(frameworks.parents[1])], check=True)

with tempfile.TemporaryDirectory(prefix='stats-settings-') as temporary:
    directory = Path(temporary)
    identifier = uuid.uuid4().hex
    executable_name = 'stats-settings-checks-' + identifier
    bundle_identifier = 'local.stats.settings-checks.' + identifier
    helper = directory / ('Settings Checks ' + identifier + '.app')
    resources = helper / 'Contents/Resources'
    executable = helper / 'Contents/MacOS' / executable_name
    resources.mkdir(parents=True)
    executable.parent.mkdir(parents=True)
    # A distinct temporary app identity is required by the real Notifications
    # settings' initIDs/removeNotification calls. It never shares the Stats
    # preference or notification domain, requests authorization, or sends alerts.
    with (helper / 'Contents/Info.plist').open('wb') as destination:
        plistlib.dump({
            'CFBundleIdentifier': bundle_identifier,
            'CFBundleExecutable': executable_name,
            'CFBundleName': 'Isolated Settings Checks',
            'CFBundlePackageType': 'APPL',
            'CFBundleVersion': '1',
            'LSUIElement': True,
        }, destination)
    # All localized strings and model artwork come from the matching build.
    for language in (frameworks.parent / 'Resources').glob('*.lproj'):
        shutil.copytree(language, resources / language.name)
    catalog = frameworks.parent / 'Resources/Assets.car'
    if catalog.is_file():
        shutil.copy2(catalog, resources / catalog.name)
    sources = [Path(__file__).resolve().with_name('settings-layout.swift')]
    defines = []
    if not args.render_only:
        # Compile the actual internal Sensors.Settings class and its production
        # value models and settings pages into this isolated helper. Do not
        # create Sensors.main, readers, or a production application delegate;
        # the popup fixture contains no Fan models and invokes no fan actions.
        sources.extend([
            root / 'Modules/Sensors/settings.swift',
            root / 'Modules/Sensors/values.swift',
            root / 'Modules/Sensors/popup.swift',
            root / 'Modules/Sensors/notifications.swift',
            root / 'Modules/Sensors/Local/FanCurveController.swift',
            Path(__file__).resolve().with_name('sensors-settings-layout.swift'),
        ])
        defines = ['-D', 'SETTINGS_REAL_SENSORS']
    subprocess.run([
        'xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library',
        '-O', '-whole-module-optimization', '-module-name', 'SettingsLayoutChecks',
        '-module-cache-path', '/tmp/stats-settings-module-cache',
        '-I', str(args.build_dir / 'modules'), '-F', str(frameworks), '-framework', 'Kit',
        '-Xlinker', '-rpath', '-Xlinker', str(frameworks),
        *defines, *map(str, sources), '-o', str(executable)
    ], check=True)
    subprocess.run(['/usr/bin/codesign', '--force', '--sign', '-', '--timestamp=none', str(helper)],
                   check=True)
    subprocess.run([*preflight, str(helper)], check=True)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    command = [str(executable), '--output-dir', str(args.output_dir),
               '--resource-app', str(frameworks.parents[1])]
    if args.render_only:
        command.append('--render-only')
    if args.locale:
        command.extend(['-AppleLocale', args.locale])
    if args.language:
        command.extend(['-AppleLanguages', '(' + args.language + ')'])
    subprocess.run(command, check=True, timeout=60)
