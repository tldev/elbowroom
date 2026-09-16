#!/usr/bin/env python3
"""Dorso-style direct releases, with one version and changelog source of truth."""
import argparse
import base64
from datetime import date, datetime, timezone
from email.utils import format_datetime
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
SPARKLE = ROOT / '.build/artifacts/sparkle/Sparkle/bin'
NS = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', NS)


def run(*args, capture=False):
    print('+ ' + ' '.join(map(str, args)), flush=True)
    result = subprocess.run(list(map(str, args)), cwd=ROOT, check=True,
                            stdout=subprocess.PIPE if capture else None, text=True)
    return result.stdout.strip() if capture else None


def version_tuple(value):
    if not re.fullmatch(r'(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)', value):
        raise ValueError('Use a stable semantic version X.Y.Z, without a v prefix or leading zeroes.')
    return tuple(map(int, value.split('.')))


def metadata():
    value = json.loads((ROOT / 'release.json').read_text())
    version_tuple(value['version'])
    if type(value['build']) is not int or value['build'] < 1:
        raise ValueError('build must be a positive, monotonically increasing integer')
    if value['repository'] != 'tldev/elbowroom' or value['bundle_id'] != 'dev.elbowroom.app':
        raise ValueError('Release identity must be Elbowroom, preserving its existing bundle ID.')
    return value


def changelog_section(text, version):
    pattern = rf'^## \[{re.escape(version)}\] - (\d{{4}}-\d{{2}}-\d{{2}})\s*\n(.*?)(?=^## |\Z)'
    matches = list(re.finditer(pattern, text, re.M | re.S))
    if len(matches) != 1:
        raise ValueError(f'Add exactly one dated CHANGELOG.md entry for {version}.')
    date.fromisoformat(matches[0][1])
    body = matches[0][2].strip()
    if not re.search(r'^- \S', body, re.M):
        raise ValueError('Release notes need at least one user-facing change.')
    return body


def notes(meta):
    body = changelog_section((ROOT / 'CHANGELOG.md').read_text(), meta['version'])
    return (f"## What's new\n\n{body}\n\n## Installation\n\n"
            '1. Open the DMG and drag Elbowroom to Applications, or unzip the ZIP and move the app there.\n'
            '2. Open Elbowroom from Applications.\n'
            '3. Follow the in-app Full Disk Access instructions to scan protected folders.\n\n'
            f"Requires macOS {meta['minimum_macos']} or later. Supports Apple Silicon and Intel.\n"
            'All features are free, with no usage limits or paid upgrades.\n')


def bump(kind):
    meta = metadata()
    major, minor, patch = version_tuple(meta['version'])
    version = {'major': (major + 1, 0, 0), 'minor': (major, minor + 1, 0),
               'patch': (major, minor, patch + 1)}[kind]
    text = (ROOT / 'CHANGELOG.md').read_text()
    match = re.search(r'^## \[Unreleased\]\s*\n(.*?)(?=^## |\Z)', text, re.M | re.S)
    if not match or not re.search(r'^- \S', match[1], re.M):
        raise ValueError('Write changes under CHANGELOG.md [Unreleased] before bumping.')
    meta['version'] = '.'.join(map(str, version))
    meta['build'] += 1
    heading = f"## [Unreleased]\n\n## [{meta['version']}] - {date.today().isoformat()}\n\n"
    text = text[:match.start()] + heading + match[1].strip() + '\n\n' + text[match.end():]
    (ROOT / 'CHANGELOG.md').write_text(text)
    (ROOT / 'release.json').write_text(json.dumps(meta, indent=2) + '\n')
    print(f"Prepared {meta['version']} (build {meta['build']}). Review and commit before publishing.")


def setup_key(meta):
    if not (SPARKLE / 'generate_keys').exists():
        run('swift', 'package', 'resolve')
    if meta['sparkle_public_key']:
        existing = run(SPARKLE / 'generate_keys', '--account', meta['sparkle_key_account'], '-p', capture=True)
        if existing != meta['sparkle_public_key']:
            raise ValueError('Existing public key differs. Restore the original key; do not silently rotate it.')
        print('Existing Elbowroom signing key verified.')
        return
    # Separate keychain account; never export or print the private key.
    run(SPARKLE / 'generate_keys', '--account', meta['sparkle_key_account'])
    public = run(SPARKLE / 'generate_keys', '--account', meta['sparkle_key_account'], '-p', capture=True)
    if len(base64.b64decode(public, validate=True)) != 32:
        raise ValueError('Sparkle did not return a valid public key.')
    meta['sparkle_public_key'] = public
    (ROOT / 'release.json').write_text(json.dumps(meta, indent=2) + '\n')


def preflight(meta, publish=False, preview=False, ci=False):
    for cmd in ['swift', 'xcrun', 'codesign', 'ditto', 'hdiutil', 'create-dmg', 'git']:
        if not shutil.which(cmd):
            raise ValueError(f'Missing {cmd}. For create-dmg, run: brew install create-dmg')
    identities = run('security', 'find-identity', '-v', '-p', 'codesigning', capture=True)
    if not preview and 'Developer ID Application:' not in identities:
        raise ValueError('Install a Developer ID Application certificate before distribution.')
    notes(meta)
    if not preview:
        key = meta['sparkle_public_key']
        if not key or len(base64.b64decode(key, validate=True)) != 32:
            raise ValueError('Run ./release.sh --setup-key before distribution.')
        if not (SPARKLE / 'generate_keys').exists():
            run('swift', 'package', 'resolve')
        public = run(SPARKLE / 'generate_keys', '--account', meta['sparkle_key_account'], '-p', capture=True)
        if public != key:
            raise ValueError('The keychain signing key does not match release.json.')
        run('xcrun', 'notarytool', 'history', '--keychain-profile',
            os.getenv('NOTARY_PROFILE', meta['notary_profile']), '--output-format', 'json', *notary_keychain_args(), capture=True)
    tag = 'v' + meta['version']
    # Read both GitHub releases and remote tags; never replace a published version.
    if not preview:
        run('gh', 'auth', 'status', capture=True)
        releases = json.loads(run('gh', 'release', 'list', '--repo', meta['repository'],
                                 '--limit', '100', '--json', 'tagName,isDraft', capture=True))
        if any(r['tagName'] == tag for r in releases):
            raise ValueError(f'{tag} already has a GitHub release (including drafts).')
        remote = run('git', 'ls-remote', '--tags', 'origin', capture=True)
        remote_tags = [line.split('refs/tags/', 1)[1] for line in remote.splitlines()]
        local_tags = run('git', 'tag', '--list', capture=True).splitlines()
        all_tags = set(remote_tags + local_tags)
        if tag in all_tags:
            raise ValueError(f'{tag} already exists. Bump the version; never replace tags.')
        stable_tags = [t[1:] for t in all_tags if re.fullmatch(r'v\d+\.\d+\.\d+', t)]
        if any(version_tuple(v) >= version_tuple(meta['version']) for v in stable_tags):
            raise ValueError('The new semantic version must exceed all existing stable tags.')
    feed = ET.parse(ROOT / 'appcast.xml')
    builds = [int(x.text) for x in feed.findall(f'.//{{{NS}}}version')]
    if builds and meta['build'] <= max(builds):
        raise ValueError('The build number must exceed every published appcast build.')
    if publish:
        origin = run('git', 'remote', 'get-url', 'origin', capture=True)
        if origin not in [f"git@github.com:{meta['repository']}.git",
                          f"https://github.com/{meta['repository']}.git"]:
            raise ValueError('origin must point to tldev/elbowroom.')
        if run('git', 'status', '--porcelain', capture=True):
            raise ValueError('Commit the version, changelog, and app changes before publishing.')
        run('git', 'fetch', 'origin', 'main')
        if ci:
            validate_ci_source()
            run('git', 'merge-base', '--is-ancestor', 'HEAD', 'origin/main')
        else:
            if run('git', 'branch', '--show-current', capture=True) != 'main':
                raise ValueError('Publish from main after merging the reviewed changes.')
            run('git', 'merge-base', '--is-ancestor', 'origin/main', 'HEAD')
    print('Release preflight passed.', flush=True)


def notary_keychain_args():
    keychain = os.getenv('NOTARY_KEYCHAIN')
    return ['--keychain', keychain] if keychain else []


def notarize(path, profile):
    raw = run('xcrun', 'notarytool', 'submit', path, '--keychain-profile', profile,
              '--wait', '--output-format', 'json', *notary_keychain_args(), capture=True)
    result = json.loads(raw)
    path.with_suffix(path.suffix + '.notary.json').write_text(json.dumps(result, indent=2) + '\n')
    if result.get('status') != 'Accepted':
        raise ValueError(f"Notarization failed: {result.get('status')} (submission {result.get('id')}).")


def zip_app(app, destination):
    destination.unlink(missing_ok=True)
    run('ditto', '-c', '-k', '--keepParent', app, destination)


def appcast(meta, signature, size, timestamp):
    tree = ET.parse(ROOT / 'appcast.xml')
    channel = tree.getroot().find('channel')
    tag = 'v' + meta['version']
    url = f"https://github.com/{meta['repository']}/releases"
    item = ET.Element('item')
    for key, value in [('title', f"Version {meta['version']}"), ('link', f'{url}/tag/{tag}'),
                       (f'{{{NS}}}version', str(meta['build'])),
                       (f'{{{NS}}}shortVersionString', meta['version']),
                       (f'{{{NS}}}minimumSystemVersion', meta['minimum_macos']),
                       (f'{{{NS}}}releaseNotesLink', f'{url}/download/{tag}/release-notes.html'),
                       ('pubDate', format_datetime(timestamp))]:
        ET.SubElement(item, key).text = value
    ET.SubElement(item, 'enclosure', {'url': f'{url}/download/{tag}/Elbowroom-{tag}.zip',
        f'{{{NS}}}edSignature': signature, 'length': str(size), 'type': 'application/octet-stream'})
    channel.insert(0, item)
    ET.indent(tree, space='  ')
    return ET.tostring(tree.getroot(), encoding='unicode', xml_declaration=True) + '\n'


def package(meta, preview):
    version = meta['version']
    folder = ROOT / 'dist' / ('previews' if preview else 'releases') / version
    folder.parent.mkdir(parents=True, exist_ok=True)
    if folder.exists():
        raise ValueError(f'{folder} already exists. Move that local output aside before rebuilding.')
    work = Path(tempfile.mkdtemp(prefix=f'.{version}-', dir=folder.parent))
    print(f'Building in {work}', flush=True)
    source = run('git', 'rev-parse', 'HEAD', capture=True)
    dirty = bool(run('git', 'status', '--porcelain', capture=True))
    app = work / 'Elbowroom.app'
    args = ['bash', 'Scripts/make-app.sh', 'release', '--output', app]
    args += ['--distribution'] if not preview else []
    run(*args)
    archive = work / f'Elbowroom-v{version}.zip'
    dmg = work / f'Elbowroom-v{version}.dmg'
    zip_app(app, archive)
    if not preview:
        profile = os.getenv('NOTARY_PROFILE', meta['notary_profile'])
        notarize(archive, profile)
        run('xcrun', 'stapler', 'staple', app)
        run('xcrun', 'stapler', 'validate', app)
        zip_app(app, archive)
    run('bash', 'Scripts/make-dmg.sh', app, dmg)
    if not preview:
        identities = run('security', 'find-identity', '-v', '-p', 'codesigning', capture=True)
        identity = os.getenv('DEVELOPER_ID') or re.search(r'([A-F0-9]{40}) "Developer ID Application:', identities)[1]
        run('codesign', '--force', '--sign', identity, '--timestamp', dmg)
        notarize(dmg, profile)
        run('xcrun', 'stapler', 'staple', dmg)
        run('xcrun', 'stapler', 'validate', dmg)
        run('spctl', '--assess', '--type', 'execute', '--verbose=2', app)
        attrs = run(SPARKLE / 'sign_update', '--account', meta['sparkle_key_account'], archive, capture=True)
        parsed = ET.fromstring(f'<enclosure xmlns:sparkle="{NS}" {attrs}/>')
        if int(parsed.attrib['length']) != archive.stat().st_size:
            raise ValueError('Sparkle signature length does not match the release ZIP.')
        run(SPARKLE / 'sign_update', '--account', meta['sparkle_key_account'], '--verify',
            archive, parsed.attrib[f'{{{NS}}}edSignature'])
        (work / 'appcast.xml').write_text(appcast(meta, parsed.attrib[f'{{{NS}}}edSignature'],
                                               archive.stat().st_size, datetime.now(timezone.utc)))
    release_notes = notes(meta)
    (work / 'release-notes.md').write_text(release_notes)
    # A readable, escaped HTML document for Sparkle's release-notes window.
    import html
    (work / 'release-notes.html').write_text('<!doctype html><meta charset="utf-8">'
        '<style>body{font:15px -apple-system,sans-serif;line-height:1.6;padding:20px}pre{white-space:pre-wrap;font:inherit}</style>'
        '<pre>' + html.escape(release_notes) + '</pre>\n')
    hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in [archive, dmg]}
    (work / 'SHA256SUMS').write_text(''.join(f'{sha}  {name}\n' for name, sha in hashes.items()))
    (work / 'release-manifest.json').write_text(json.dumps(dict(
        version=version, build=meta['build'], commit=source, dirty=dirty,
        notarized=not preview, sha256=hashes), indent=2) + '\n')
    work.rename(folder)
    print(f'Artifacts ready: {folder}', flush=True)
    return folder


def publish(meta, folder, ci=False):
    manifest = json.loads((folder / 'release-manifest.json').read_text())
    if manifest['dirty'] or not manifest['notarized']:
        raise ValueError('Only a clean, notarized build can be published.')
    if run('git', 'status', '--porcelain', capture=True) or run('git', 'rev-parse', 'HEAD', capture=True) != manifest['commit']:
        raise ValueError('Source changed during packaging. Rebuild the release from a clean commit.')
    for name, expected in manifest['sha256'].items():
        if hashlib.sha256((folder / name).read_bytes()).hexdigest() != expected:
            raise ValueError(f'Artifact changed after signing: {name}')
    tag = 'v' + meta['version']
    run('git', 'tag', '-a', tag, '-m', f'Elbowroom {tag}')
    if ci:
        validate_ci_source()
        run('git', 'push', 'origin', f'refs/tags/{tag}')
    else:
        run('git', 'push', '--atomic', 'origin', 'HEAD:refs/heads/main', f'refs/tags/{tag}')
    run('gh', 'release', 'create', tag, folder / f'Elbowroom-{tag}.dmg', folder / f'Elbowroom-{tag}.zip',
        folder / 'release-notes.html', folder / 'SHA256SUMS', folder / 'appcast.xml', '--repo', meta['repository'], '--verify-tag',
        '--title', f'Elbowroom {tag}', '--notes-file', folder / 'release-notes.md')
    # Only advertise the update after its downloadable assets are public.
    if ci:
        # Build/tag the triggering commit, but add the feed on current main so
        # an unrelated merge during notarization is never reverted.
        run('git', 'fetch', 'origin', 'main')
        run('git', 'checkout', '--detach', 'origin/main')
    shutil.copy2(folder / 'appcast.xml', ROOT / 'appcast.xml')
    run('git', 'add', '--', 'appcast.xml')
    run('git', 'commit', '-m', f'Publish update feed for {tag}', '--', 'appcast.xml')
    run('git', 'push', 'origin', 'HEAD:refs/heads/main')
    print(f"Published https://github.com/{meta['repository']}/releases/tag/{tag}")


def validate_ci_source():
    if os.getenv('GITHUB_REF') != 'refs/heads/main' or os.getenv('GITHUB_EVENT_NAME') not in ('push', 'workflow_dispatch'):
        raise ValueError('CI publication is only allowed for main pushes or a main workflow dispatch.')
    if os.getenv('GITHUB_REPOSITORY') != 'tldev/elbowroom':
        raise ValueError('CI publication must run in tldev/elbowroom.')
    if run('git', 'rev-parse', 'HEAD', capture=True) != os.getenv('GITHUB_SHA'):
        raise ValueError('The checkout does not match the triggering merge commit.')


def release_pending(meta):
    notes(meta)
    tag = 'v' + meta['version']
    releases = json.loads(run('gh', 'release', 'list', '--repo', meta['repository'],
                             '--limit', '100', '--json', 'tagName,isDraft', capture=True))
    matching = [r for r in releases if r['tagName'] == tag]
    if matching and matching[0]['isDraft']:
        raise ValueError(f'{tag} has an unfinished draft release; recover it before retrying.')
    pending = not matching
    if not pending:
        tree = ET.parse(ROOT / 'appcast.xml')
        versions = [item.findtext(f'{{{NS}}}shortVersionString') for item in tree.findall('channel/item')]
        if meta['version'] not in versions:
            raise ValueError(f'{tag} is published but its update feed is missing. Recover the appcast asset.')
    print(f'{tag}: ' + ('new version, release required' if pending else 'already published; no release needed'))
    if output := os.getenv('GITHUB_OUTPUT'):
        with open(output, 'a') as f:
            f.write(f'pending={str(pending).lower()}\nversion={meta["version"]}\n')
    return pending


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('version', nargs='?')
    parser.add_argument('--ci', action='store_true', help='Publish the exact main commit selected by GitHub Actions')
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument('--pending', action='store_true', help='Report whether this version needs a merge-triggered release')
    modes.add_argument('--check', action='store_true', help='Validate a publishable checkout and credentials without building')
    modes.add_argument('--preview', action='store_true', help='Host-architecture installer preview; no notarization or publication')
    modes.add_argument('--publish', action='store_true', help='Build, notarize, tag, push, publish on GitHub, then update the feed')
    modes.add_argument('--setup-key', action='store_true', help='Create/read the separate Elbowroom Sparkle keychain key')
    modes.add_argument('--bump', choices=['patch', 'minor', 'major'], help='Promote Unreleased notes and increment version/build')
    args = parser.parse_args()
    meta = metadata()
    if args.pending:
        release_pending(meta)
        return
    if args.ci and not (args.publish or args.check):
        raise ValueError('--ci must be used with --publish or --check.')
    if args.bump:
        bump(args.bump)
        return
    if args.setup_key:
        setup_key(meta)
        return
    if args.version and args.version != meta['version']:
        raise ValueError(f"Requested version differs from release.json ({meta['version']}).")
    preflight(meta, publish=args.publish or args.check, preview=args.preview, ci=args.ci)
    if args.check:
        return
    folder = package(meta, args.preview)
    if args.publish:
        publish(meta, folder, ci=args.ci)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, subprocess.CalledProcessError, OSError) as error:
        print(f'Release stopped: {error}', file=sys.stderr)
        sys.exit(1)
