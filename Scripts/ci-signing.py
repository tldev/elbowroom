#!/usr/bin/env python3
"""Install release credentials into an ephemeral GitHub runner keychain."""
import base64
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
folder = Path(os.environ['RUNNER_TEMP']) / 'elbowroom-signing'
keychain = folder / 'release.keychain-db'


def run(*args):
    # Never log command arguments: they can contain credentials.
    result = subprocess.run([str(arg) for arg in args], stdout=subprocess.DEVNULL)
    if result.returncode:
        raise RuntimeError(f'{Path(args[0]).name} failed (exit {result.returncode}); arguments omitted to protect credentials')


def cleanup():
    if keychain.exists():
        run('security', 'default-keychain', '-d', 'user', '-s',
            Path.home() / 'Library/Keychains/login.keychain-db')
        run('security', 'delete-keychain', keychain)
    shutil.rmtree(folder, ignore_errors=True)


def setup():
    for name in ['CERTIFICATE_P12', 'CERTIFICATE_PASSWORD', 'SPARKLE_PRIVATE_KEY',
                 'APPLE_ID', 'APPLE_APP_PASSWORD']:
        if not os.environ.get(name):
            raise RuntimeError(f'Missing repository secret for {name}')
    folder.mkdir(mode=0o700)
    password = secrets.token_urlsafe(40)
    certificate = folder / 'identity.p12'
    certificate.write_bytes(base64.b64decode(os.environ['CERTIFICATE_P12'], validate=True))
    certificate.chmod(0o600)
    sparkle = folder / 'sparkle.key'
    sparkle.write_text(os.environ['SPARKLE_PRIVATE_KEY'])
    sparkle.chmod(0o600)
    run('security', 'create-keychain', '-p', password, keychain)
    run('security', 'set-keychain-settings', '-lut', '21600', keychain)
    run('security', 'unlock-keychain', '-p', password, keychain)
    run('security', 'import', certificate, '-k', keychain, '-P',
        os.environ['CERTIFICATE_PASSWORD'], '-T', '/usr/bin/codesign', '-T', '/usr/bin/security')
    run('security', 'set-key-partition-list', '-S', 'apple-tool:,apple:,codesign:',
        '-k', password, keychain)
    # The runner is ephemeral. Make both imported Sparkle and notarization keys
    # land in this same disposable keychain.
    run('security', 'list-keychains', '-d', 'user', '-s', keychain,
        Path.home() / 'Library/Keychains/login.keychain-db')
    run('security', 'default-keychain', '-d', 'user', '-s', keychain)
    run('xcrun', 'notarytool', 'store-credentials', os.environ['NOTARY_PROFILE'],
        '--apple-id', os.environ['APPLE_ID'], '--password', os.environ['APPLE_APP_PASSWORD'],
        '--team-id', 'KBF2YGT2KP', '--keychain', keychain)
    meta = json.loads((root / 'release.json').read_text())
    run(root / '.build/artifacts/sparkle/Sparkle/bin/generate_keys',
        '--account', meta['sparkle_key_account'], '-f', sparkle)
    certificate.unlink()
    sparkle.unlink()
    with open(os.environ['GITHUB_ENV'], 'a') as env:
        env.write(f'NOTARY_KEYCHAIN={keychain}\n')
    print('Developer ID, notarization, and Sparkle credentials installed.')


if sys.argv[1:] == ['setup']:
    setup()
elif sys.argv[1:] == ['cleanup']:
    cleanup()
else:
    raise SystemExit('Usage: ci-signing.py setup|cleanup')
