#!/usr/bin/env python3
"""Check a local app or executable without launching it. Requires macOS 14+."""
import argparse
import os
from pathlib import Path
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('path', type=Path)
    args = parser.parse_args()
    target = args.path.resolve(strict=True)
    gatekeeper = Path('/usr/bin/gktool')
    if not gatekeeper.is_file():
        raise SystemExit('Gatekeeper preflight unavailable; target was not launched.')
    subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(target)],
                   check=True, timeout=30)
    result = subprocess.run([str(gatekeeper), 'scan', str(target)],
                            capture_output=True, text=True, timeout=60,
                            env={**os.environ, 'LC_ALL': 'C'})
    output = result.stdout + result.stderr
    allowed = 'Scan completed and software is allowed by system policy.'
    if result.returncode or allowed not in output:
        print('\n'.join(output.replace('\r', '\n').splitlines()[-12:]), file=sys.stderr)
        raise SystemExit('Gatekeeper preflight did not allow the target; target was not launched.')
    print('Signature verified; Gatekeeper allows: ' + str(target))


if __name__ == '__main__':
    main()
