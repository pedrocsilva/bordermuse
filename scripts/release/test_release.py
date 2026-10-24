import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest

from release import asset_names, plan, verify


class ReleasePlanTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.git('init', '-b', 'main')
        self.git('config', 'user.name', 'Release test')
        self.git('config', 'user.email', 'release@example.invalid')
        info = self.root / 'apps/macos/BorderMuse/Resources/Info.plist'
        info.parent.mkdir(parents=True)
        info.write_bytes(plistlib.dumps({'CFBundleShortVersionString': '0.1.0'}))
        self.git('add', '.')
        self.git('commit', '-m', 'Fixture')
        self.commit = self.git('rev-parse', 'HEAD')
        self.git('update-ref', 'refs/remotes/origin/main', self.commit)

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.root), *args], text=True, stderr=subprocess.DEVNULL).strip()

    def check(self, event='push', ref='refs/tags/v0.1.0-alpha.2', commit=None):
        return plan(event, ref, commit or self.commit, root=self.root)

    def test_annotated_tag_and_manual_dry_run(self):
        self.git('tag', '-a', 'v0.1.0-alpha.2', '-m', 'Alpha')
        tagged = self.check()
        self.assertTrue(tagged['publish'])
        self.assertEqual(tagged['commit'], self.commit)
        self.assertEqual(tagged['version'], '0.1.0-alpha.2')
        manual = self.check('workflow_dispatch', 'refs/heads/main')
        self.assertFalse(manual['publish'])
        self.assertEqual(manual['version'], '0.1.0-alpha.0')
        self.assertEqual(self.git('tag', '--list'), 'v0.1.0-alpha.2')

    def test_rejects_stable_malformed_and_mismatched_versions(self):
        for tag in ['v0.1.0', 'v0.1.0-alpha.0', 'v0.1.0-alpha.01', 'v0.1.0-preview.1',
                    'v0.2.0-alpha.1', 'v01.1.0-alpha.1', 'v0.1.0-alpha.1;id']:
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                self.check(ref='refs/tags/' + tag)
        with self.assertRaises(ValueError):
            self.check(ref='refs/heads/main')
        with self.assertRaises(ValueError):
            self.check(commit='0' * 40)

    def test_rejects_dirty_source(self):
        (self.root / 'uncommitted').write_text('not part of the commit')
        with self.assertRaisesRegex(ValueError, 'clean checkout'):
            self.check('workflow_dispatch', 'refs/heads/main')

    def test_requires_tag_commit_and_main_ancestry(self):
        self.git('tag', 'v0.1.0-alpha.2')
        (self.root / 'extra').write_text('new commit')
        self.git('add', '.')
        self.git('commit', '-m', 'New commit')
        newer = self.git('rev-parse', 'HEAD')
        self.git('update-ref', 'refs/remotes/origin/main', newer)
        with self.assertRaises(ValueError):
            self.check(commit=newer)
        self.git('update-ref', 'refs/remotes/origin/main', self.commit)
        with self.assertRaises(subprocess.CalledProcessError):
            self.check('workflow_dispatch', 'refs/heads/main', newer)


class ReleaseArtifactTests(unittest.TestCase):
    version = '0.1.0-alpha.2'
    commit = 'a' * 40

    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.manifest = {
            'product': 'Border Muse', 'version': self.version, 'appVersion': '0.1.0',
            'sourceCommit': self.commit, 'architectures': ['x86_64', 'arm64'],
            'signature': 'ad-hoc', 'notarized': False, 'minimumMacOS': '14.0',
            'geometryContract': 'bordermuse-geometry-v1',
        }
        for name in asset_names(self.version)[:2]:
            (self.root / name).write_bytes(b'fixture archive bytes')
        self.write_manifest()

    def write_manifest(self):
        (self.root / 'release-manifest.json').write_text(json.dumps(self.manifest))
        self.checksums()

    def checksums(self):
        (self.root / 'SHA256SUMS.txt').write_text(''.join(
            hashlib.sha256((self.root / name).read_bytes()).hexdigest() + '  ' + name + '\n'
            for name in asset_names(self.version)))

    def test_accepts_complete_artifacts_and_optional_notes(self):
        self.assertEqual(verify(self.root, self.version, self.commit), self.manifest)
        (self.root / 'release-notes.md').write_text('Notes')
        verify(self.root, self.version, self.commit)

    def test_rejects_tampering_extra_missing_and_symlinked_files(self):
        archive = self.root / asset_names(self.version)[0]
        original = archive.read_bytes()
        archive.write_bytes(b'tampered')
        with self.assertRaisesRegex(ValueError, 'Checksum mismatch'):
            verify(self.root, self.version, self.commit)
        archive.write_bytes(original)
        extra = self.root / 'unexpected.zip'
        extra.write_bytes(b'extra')
        with self.assertRaises(ValueError):
            verify(self.root, self.version, self.commit)
        extra.unlink()
        archive.unlink()
        with self.assertRaises(ValueError):
            verify(self.root, self.version, self.commit)
        archive.symlink_to(self.root / 'release-manifest.json')
        with self.assertRaises(ValueError):
            verify(self.root, self.version, self.commit)

    def test_rejects_wrong_source_architectures_signing_and_contract(self):
        for field, value in [('sourceCommit', 'b' * 40), ('architectures', ['arm64']),
                             ('notarized', True), ('geometryContract', 'v2')]:
            with self.subTest(field=field):
                previous = self.manifest[field]
                self.manifest[field] = value
                self.write_manifest()
                with self.assertRaises(ValueError):
                    verify(self.root, self.version, self.commit)
                self.manifest[field] = previous
        self.write_manifest()
        text = (self.root / 'SHA256SUMS.txt').read_text()
        for invalid in [text + text.splitlines()[0] + '\n', text.replace('release-manifest.json', '../outside')]:
            (self.root / 'SHA256SUMS.txt').write_text(invalid)
            with self.assertRaises(ValueError):
                verify(self.root, self.version, self.commit)


if __name__ == '__main__':
    unittest.main()
