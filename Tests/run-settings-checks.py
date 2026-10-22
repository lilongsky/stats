#!/usr/bin/env python3
"""Check production settings views in isolation and save private offscreen previews."""
from pathlib import Path
import argparse
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
    # NSLocalizedString in Kit uses Bundle.main. Keep the helper's translations
    # beside its bare executable, using resources from the matching built app.
    for language in (frameworks.parent / 'Resources').glob('*.lproj'):
        shutil.copytree(language, directory / language.name)
    executable = directory / ('stats-settings-checks-' + uuid.uuid4().hex)
    subprocess.run([
        'xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library',
        '-O', '-whole-module-optimization', '-module-name', 'SettingsLayoutChecks',
        '-module-cache-path', '/tmp/stats-settings-module-cache',
        '-I', str(args.build_dir / 'modules'), '-F', str(frameworks), '-framework', 'Kit',
        '-Xlinker', '-rpath', '-Xlinker', str(frameworks),
        str(Path(__file__).resolve().with_name('settings-layout.swift')), '-o', str(executable)
    ], check=True)
    subprocess.run([*preflight, str(executable)], check=True)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    command = [str(executable), '--output-dir', str(args.output_dir)]
    if args.render_only:
        command.append('--render-only')
    if args.locale:
        command.extend(['-AppleLocale', args.locale])
    if args.language:
        command.extend(['-AppleLanguages', '(' + args.language + ')'])
    subprocess.run(command, check=True, timeout=60)
