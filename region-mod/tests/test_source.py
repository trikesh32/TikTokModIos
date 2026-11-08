import copy
import importlib.util
import json
from pathlib import Path
import plistlib
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).parents[1] / 'scripts'))
from compatibility import sha256
from package import altstore_entitlements, package
from source import generate, https


class SourceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.ipa = Path(self.temp.name) / 'app.ipa'
        self.info = {'CFBundleIdentifier': 'com.zhiliaoapp.musically',
                     'CFBundleShortVersionString': '47.6.0', 'CFBundleVersion': '476038.1100',
                     'TTDistribution': 'altstore-classic', 'TTCompatibilityBuild': '1.1.0',
                     'MinimumOSVersion': '15.0'}
        self.write_ipa()

    def write_ipa(self, profile=False):
        with zipfile.ZipFile(self.ipa, 'w') as z:
            z.writestr('Payload/TikTok.app/Info.plist', plistlib.dumps(self.info))
            if profile:
                z.writestr('Payload/TikTok.app/embedded.mobileprovision', b'fixture')
        self.report = {'sha256': sha256(self.ipa), 'distribution': 'altstore-classic',
                       'adhoc_signature_verified': True, 'zip_crc_verified': True,
                       'app_version': self.info['CFBundleShortVersionString'],
                       'app_build': self.info['CFBundleVersion'],
                       'app_permissions': {'entitlements': ['keychain-access-groups'],
                                           'privacy': {'NSCameraUsageDescription': 'Camera fixture'}}}
        self.write_report()

    def write_report(self):
        self.ipa.with_suffix('.verification.json').write_text(json.dumps(self.report))

    def generate(self, **kwargs):
        return generate(self.ipa, 'https://example.org/app.ipa', 'https://example.org/icon.png', '2026-11-08', **kwargs)

    def test_metadata_size_permissions_and_version_come_from_ipa(self):
        feed = self.generate()
        app = feed['apps'][0]
        self.assertEqual(app['versions'][0]['buildVersion'], self.info['CFBundleVersion'])
        self.assertEqual(app['versions'][0]['size'], self.ipa.stat().st_size)
        self.assertEqual(app['appPermissions'], self.report['app_permissions'])
        self.assertEqual(app['versions'][0]['minOSVersion'], '15.0')

    def test_modified_artifact_rejected(self):
        self.report['sha256'] = '0' * 64
        self.write_report()
        with self.assertRaises(ValueError): self.generate()

    def test_personal_profile_and_identity_rejected(self):
        self.write_ipa(profile=True)
        with self.assertRaises(ValueError): self.generate()
        self.info['CFBundleIdentifier'] += '.PERSONAL'
        self.write_ipa()
        with self.assertRaises(ValueError): self.generate()

    def test_version_mismatch_and_local_signer_rejected(self):
        for field, value in [('app_build', 'wrong'), ('distribution', 'local-signer')]:
            self.write_ipa()
            self.report[field] = value
            self.write_report()
            with self.subTest(field=field), self.assertRaises(ValueError): self.generate()

    def test_update_is_prepended_duplicate_rejected(self):
        first = self.generate()
        with self.assertRaises(ValueError): self.generate(existing=first)
        self.info['CFBundleVersion'] = '476038.1101'
        self.write_ipa()
        second = self.generate(existing=first)
        self.assertEqual([v['buildVersion'] for v in second['apps'][0]['versions']], ['476038.1101', '476038.1100'])

    def test_urls_exclude_credentials_non_https_and_fragments(self):
        for url in ('http://example.org', 'https://user:secret@example.org', 'file:///tmp/a', 'https://example.org/#token'):
            with self.subTest(url=url), self.assertRaises(ValueError): https(url)

    def test_altstore_team_rewrite_preserves_isolated_groups(self):
        groups = altstore_entitlements()['keychain-access-groups']
        self.assertEqual(len(groups), 7)
        rewritten = ['TESTTEAM01.' + g.split('.', 1)[1] for g in groups]
        self.assertIn('TESTTEAM01.com.zhiliaoapp.musically.altstore.compat.chainlogin', rewritten)
        self.assertTrue(all(g.startswith('TESTTEAM01.com.zhiliaoapp.musically.altstore') for g in rewritten))

    def test_altstore_requires_manifest(self):
        with self.assertRaisesRegex(ValueError, 'manifest'):
            package(Path('unused'), None, Path('unused-output'), altstore=True)


if __name__ == '__main__':
    unittest.main()
