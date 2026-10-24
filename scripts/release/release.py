#!/usr/bin/env python3
"""Plan and verify experimental releases; no credentials or publishing side effects."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
NUMBER = r'(?:0|[1-9][0-9]*)'
CORE = rf'{NUMBER}\.{NUMBER}\.{NUMBER}'
PRERELEASE = re.compile(rf'({CORE})-(alpha|beta|rc)\.([1-9][0-9]*)\Z')
SHA = re.compile(r'[0-9a-f]{40}\Z')


def require(condition, message):
    if not condition:
        raise ValueError(message)


def git(*args, root=ROOT):
    return subprocess.check_output(['git', '-C', str(root), *args], text=True).strip()


def plan(event, ref, expected_commit, root=ROOT):
    require(event in {'push', 'workflow_dispatch'}, 'Unsupported release event')
    require(SHA.fullmatch(expected_commit), 'Expected a full commit SHA')
    commit = git('rev-parse', 'HEAD', root=root)
    require(commit == expected_commit, 'Checkout differs from workflow commit')
    require(not git('status', '--porcelain', root=root), 'Release planning requires a clean checkout')
    subprocess.run(['git', '-C', str(root), 'merge-base', '--is-ancestor', commit, 'origin/main'], check=True)
    info = plistlib.loads((root / 'apps/macos/BorderMuse/Resources/Info.plist').read_bytes())
    core = info['CFBundleShortVersionString']
    require(re.fullmatch(CORE, core), 'App version must be X.Y.Z')
    if event == 'push':
        require(ref.startswith('refs/tags/v'), 'Only version tag pushes can publish')
        tag = ref.removeprefix('refs/tags/')
        version = tag[1:]
        match = PRERELEASE.fullmatch(version)
        require(match is not None, 'Use vX.Y.Z-alpha.N, -beta.N or -rc.N; stable publishing is disabled')
        require(match[1] == core, 'Tag and app numeric version differ')
        require(git('rev-parse', ref + '^{commit}', root=root) == commit, 'Tag differs from checkout')
    else:
        # A manual run packages the checked-out app; this synthetic version is never tagged.
        version = core + '-alpha.0'
        tag = 'v' + version
    return {'version': version, 'tag': tag, 'commit': commit, 'publish': event == 'push'}


def asset_names(version):
    stem = f'BorderMuse-{version}-macos-universal'
    return [stem + '.zip', stem + '.dmg', 'release-manifest.json']


def verify(directory, version, commit):
    require(re.fullmatch(rf'{CORE}-(alpha|beta|rc)\.(0|[1-9][0-9]*)', version), 'Invalid prerelease version')
    require(SHA.fullmatch(commit), 'Expected a full source commit')
    names = asset_names(version)
    expected = set(names + ['SHA256SUMS.txt'])
    actual = {p.name for p in directory.iterdir()}
    require(expected <= actual <= expected | {'release-notes.md'}, 'Unexpected or missing release files')
    require(all(p.is_file() and not p.is_symlink() for p in directory.iterdir()), 'Release files must be regular files')
    checksums = {}
    for line in (directory / 'SHA256SUMS.txt').read_text().splitlines():
        match = re.fullmatch(r'([a-f0-9]{64})  ([A-Za-z0-9._-]+)', line)
        require(match is not None, 'Malformed checksum entry')
        digest, name = match.groups()
        require(name in names and name not in checksums, 'Unexpected or duplicate checksum entry')
        checksums[name] = digest
    require(set(checksums) == set(names), 'Incomplete checksum list')
    for name, expected_hash in checksums.items():
        data = (directory / name).read_bytes()
        require(len(data) > 0, 'Empty release file: ' + name)
        require(hashlib.sha256(data).hexdigest() == expected_hash, 'Checksum mismatch: ' + name)
    manifest = json.loads((directory / 'release-manifest.json').read_text())
    require(manifest['product'] == 'Border Muse' and manifest['version'] == version, 'Manifest version/product mismatch')
    require(manifest['appVersion'] == version.split('-')[0], 'Bundle and release versions differ')
    require(manifest['sourceCommit'] == commit, 'Manifest source commit mismatch')
    require(sorted(manifest['architectures']) == ['arm64', 'x86_64'], 'Both architectures are required')
    require(manifest['signature'] == 'ad-hoc' and manifest['notarized'] is False, 'Unexpected signing status')
    require(manifest['geometryContract'] == 'bordermuse-geometry-v1', 'Unexpected geometry contract')
    require(manifest['minimumMacOS'] == '14.0', 'Unexpected minimum macOS')
    return manifest


def notes(version):
    return f'''# Border Muse {version} — macOS

Experimental universal build for Apple silicon and Intel, requiring macOS 14+.
Download the DMG or ZIP and verify it against SHA256SUMS.txt. The manifest records
the source commit, architectures and geometry contract.

**Ad hoc signed; not Developer ID signed or notarized.** macOS may block it.
Read [installation instructions](https://github.com/pedrocsilva/bordermuse/blob/main/docs/INSTALL.md).
Metadata may include location. Check the delivery plan for remaining validation.

Manual VoiceOver, drag/drop, complete keyboard navigation and live minimum-window/
appearance checks remain pending. Independent downloaded-app installation checks
on Intel and macOS 14 are also pending. This alpha is intended for early testing.

See [CHANGELOG.md](https://github.com/pedrocsilva/bordermuse/blob/v{version}/CHANGELOG.md)
for changes and [release documentation](https://github.com/pedrocsilva/bordermuse/blob/main/docs/RELEASE.md)
for validation and signing limits.
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    prepare = commands.add_parser('plan')
    prepare.add_argument('--event', required=True)
    prepare.add_argument('--ref', required=True)
    prepare.add_argument('--commit', required=True)
    check = commands.add_parser('verify')
    check.add_argument('--directory', type=Path, required=True)
    check.add_argument('--version', required=True)
    check.add_argument('--commit', required=True)
    write = commands.add_parser('notes')
    write.add_argument('--directory', type=Path, required=True)
    write.add_argument('--version', required=True)
    args = parser.parse_args()
    if args.command == 'plan':
        result = plan(args.event, args.ref, args.commit)
        if os.environ.get('GITHUB_OUTPUT'):
            with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
                for key in ['version', 'tag', 'commit']:
                    output.write(f'{key}={result[key]}\n')
        print(json.dumps(result, indent=2))
    elif args.command == 'verify':
        verify(args.directory, args.version, args.commit)
        print('Verified release checksums, manifest, architectures and source commit')
    else:
        require(re.fullmatch(rf'{CORE}-(alpha|beta|rc)\.(0|[1-9][0-9]*)', args.version), 'Invalid prerelease version')
        (args.directory / 'release-notes.md').write_text(notes(args.version))


if __name__ == '__main__':
    main()
