#!/usr/bin/env python3
"""Build the local Stats variant with the installed Command Line Tools.

The installed Stats app supplies unchanged resources, widgets and helpers.
All main-app and monitoring-framework Swift sources are rebuilt from v3.0.22.
The original application is never modified by this script.
"""
import argparse
import json
import plistlib
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / 'stats-3.0.22' if (ROOT / 'stats-3.0.22').exists() else ROOT
BUILD = ROOT / 'build'
BASE = Path('/Applications/Stats.app')
APP = BUILD / 'Stats Compact.app'


def run(args, name):
    log = BUILD / (name + '.log')
    print(name, flush=True)
    with log.open('w') as out:
        result = subprocess.run([str(x) for x in args], cwd=SOURCE, stdout=out, stderr=subprocess.STDOUT)
    if result.returncode:
        print('\n'.join(log.read_text().splitlines()[-70:]), flush=True)
        raise SystemExit(f'{name} failed ({result.returncode}); see {log}')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--only', nargs='*', help='Rebuild selected targets in an existing local app')
    args = parser.parse_args()
    # These Swift frameworks are compiled without library evolution. Rebuilding
    # Kit requires rebuilding its clients, including after private layout edits.
    if args.only is not None and 'Kit' in args.only:
        args.only = None
    BUILD.mkdir(exist_ok=True)
    if not APP.exists():
        shutil.copytree(BASE, APP, symlinks=True)
    data = subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', SOURCE / 'Stats.xcodeproj/project.pbxproj'])
    project = json.loads(data)
    objects = project['objects']
    paths = {}

    def walk(ref, parent=Path()):
        obj = objects[ref]
        path = Path(obj.get('path', ''))
        here = path if obj.get('sourceTree') == 'SOURCE_ROOT' else parent / path
        paths[ref] = here
        for child in obj.get('children', []):
            walk(child, here)

    walk(objects[project['rootObject']]['mainGroup'])
    targets = {o['name']: o for o in objects.values() if o.get('isa') == 'PBXNativeTarget'}
    sdk = subprocess.check_output(['xcrun', '--show-sdk-path'], text=True).strip()
    module_dir = BUILD / 'modules'
    module_dir.mkdir(exist_ok=True)
    frameworks = APP / 'Contents/Frameworks'
    common = ['-sdk', sdk, '-target', 'arm64-apple-macos12.0', '-swift-version', '5',
              '-O', '-whole-module-optimization', '-module-cache-path', BUILD / 'module-cache',
              '-I', module_dir, '-F', frameworks,
              '-Xlinker', '-rpath', '-Xlinker', '@executable_path/../Frameworks']

    for name in ['Kit', 'CPU', 'GPU', 'RAM', 'Disk', 'Net', 'Battery', 'Sensors', 'Bluetooth', 'Clock', 'Remote', 'Stats']:
        if args.only is not None and name not in args.only:
            continue
        target = targets[name]
        sources = []
        for phase in target['buildPhases']:
            phase = objects[phase]
            if phase['isa'] == 'PBXSourcesBuildPhase':
                sources += [paths[objects[x]['fileRef']] for x in phase['files']]
        config = objects[objects[target['buildConfigurationList']]['buildConfigurations'][-1]]['buildSettings']
        extra = []
        if name != 'Kit':
            extra += ['-framework', 'Kit']
        if name == 'Stats':
            for dependency in ['CPU', 'GPU', 'RAM', 'Disk', 'Net', 'Battery', 'Sensors', 'Bluetooth', 'Clock', 'Remote']:
                extra += ['-framework', dependency]
        object_files = []
        for source in sources:
            if source.suffix not in ['.m', '.mm', '.c']:
                continue
            dest = BUILD / f'{name}-{source.stem}.o'
            clang = ['xcrun', 'clang++' if name == 'Kit' else 'clang', '-isysroot', sdk,
                     '-target', 'arm64-apple-macos12.0', '-O2', '-fobjc-arc']
            if name == 'Kit':
                clang += ['-x', 'objective-c++', '-std=c++17', '-I', SOURCE / 'Kit/lldb/include']
            run(clang + ['-c', SOURCE / source, '-o', dest], name + '-objc')
            object_files.append(dest)
        if name == 'Kit':
            extra += ['-import-objc-header', SOURCE / 'Kit/lldb/lldb.h',
                      SOURCE / 'Kit/lldb/libleveldb.a', '-lc++']
        elif config.get('SWIFT_OBJC_BRIDGING_HEADER'):
            extra += ['-import-objc-header', SOURCE / config['SWIFT_OBJC_BRIDGING_HEADER']]
        if name in ['CPU', 'GPU', 'Sensors']:
            extra += ['-lIOReport']
        if name == 'Stats':
            output = APP / 'Contents/MacOS/Stats'
            extra += ['-parse-as-library']
        else:
            output = frameworks / f'{name}.framework/Versions/A' / name
            extra += ['-parse-as-library', '-emit-library', '-emit-module',
                      '-emit-module-path', module_dir / (name + '.swiftmodule'),
                      '-Xlinker', '-install_name', '-Xlinker', f'@rpath/{name}.framework/Versions/A/{name}']
        swift = [SOURCE / x for x in sources if x.suffix == '.swift']
        run(['xcrun', 'swiftc', '-module-name', name] + common + extra + swift + object_files + ['-o', output], name)

    info_path = APP / 'Contents/Info.plist'
    info = plistlib.loads(info_path.read_bytes())
    info.update(CFBundleIdentifier='eu.exelban.Stats.Compact', CFBundleName='Stats Compact',
                CFBundleDisplayName='Stats Compact', TeamId='local.compact',
                CFBundleVersion='850')
    info_path.write_bytes(plistlib.dumps(info))
    # NSLocalizedString in Kit uses the main app's localization bundle.
    for language in ['en', 'zh-Hans', 'zh-Hant']:
        source = SOURCE / 'Stats/Supporting Files' / (language + '.lproj/Localizable.strings')
        if source.exists():
            destination = APP / 'Contents/Resources' / (language + '.lproj/Localizable.strings')
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)
    run(['codesign', '--force', '--deep', '--sign', '-', APP], 'sign')
    run(['codesign', '--verify', '--deep', '--strict', APP], 'verify-signature')
    print(APP, flush=True)


if __name__ == '__main__':
    main()
