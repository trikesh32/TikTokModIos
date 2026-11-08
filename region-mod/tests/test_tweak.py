import importlib.util
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).parents[1] / 'scripts'
sys.path.insert(0, str(SCRIPTS))
from compatibility import Metadata, compare_methods, load_manifest, require_compatible, sha256
from package import package
import tweak


def image(chained=False, base=0):
    data = bytearray(4096)
    struct.pack_into('<8I', data, 0, 0xFEEDFACF, 0x100000C, 0, 6,
                     2 if chained else 1, 88 if chained else 72, 0, 0)
    struct.pack_into('<II16sQQQQiiII', data, 32, 0x19, 72, b'__DATA', base,
                     len(data), 0, len(data), 7, 3, 0, 0)
    if chained:
        struct.pack_into('<4I', data, 104, 0x80000034, 16, 3000, 60)
        struct.pack_into('<7I', data, 3000, 0, 28, 0, 0, 0, 0, 0)
        struct.pack_into('<II', data, 3028, 1, 8)
        struct.pack_into('<IHHQIHH', data, 3036, 24, 4096, 6, 0, 0, 1, 256)
        # Two chained pointers, separated by 16 bytes.
        struct.pack_into('<Q', data, 256, 512 | (4 << 51))
        struct.pack_into('<Q', data, 272, 528)
    return data


class TweakTests(unittest.TestCase):
    def test_release_archive_keeps_full_version_and_vendor_license(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for name in ('src', 'scripts', 'tests', 'compatibility', 'vendor/fishhook', 'build'):
                (root / name).mkdir(parents=True)
            (root / 'src/RegionCompatibility.h').write_text('#ifdef TT_REGION_AGGRESSIVE\n#define TRC_VERSION @"1.0.2"')
            (root / 'build/TikTokCompatibility-iOS.dylib').write_bytes(b'fixture')
            (root / 'compatibility/tiktok-47.6.0.json').write_text('{}')
            (root / 'UPDATE.txt').write_text('instructions')
            (root / 'vendor/fishhook/LICENSE').write_text('license fixture')
            for name in ('tweak.py', 'package.py', 'compatibility.py', 'source.py'):
                (root / 'scripts' / name).write_text('# fixture')
            with patch.object(tweak, 'ROOT', root), patch.object(tweak.subprocess, 'run'):
                result = tweak.build()
            self.assertEqual(Path(result['archive']).name, '1.0.2.zip')
            self.assertTrue(Path(result['archive']).exists())
            self.assertEqual((Path(result['tweak']) / 'fishhook-LICENSE.txt').read_text(), 'license fixture')

    def test_chains_decode_actual_sites_and_nonzero_image_base(self):
        base = 0x100000000
        data = image(True, base)
        struct.pack_into('<Q', data, 288, base + 544)
        metadata = Metadata(data)
        self.assertEqual(metadata.pointer(base + 256), base + 512)
        self.assertEqual(metadata.pointer(base + 272), base + 528)
        self.assertEqual(metadata.pointer(base + 288), base + 544)

    def test_raw_pointer_is_not_blindly_masked(self):
        data = image()
        struct.pack_into('<Q', data, 256, 512 | (4 << 51))
        with self.assertRaises(ValueError):
            Metadata(data).pointer(256)

    def test_bound_or_page_escaping_chain_rejected(self):
        for value in ((1 << 63) | 512, 512 | (1023 << 51)):
            data = image(True)
            struct.pack_into('<Q', data, 256, value)
            with self.subTest(value=value), self.assertRaises(ValueError):
                Metadata(data).pointer(256)

    def test_unknown_chain_format_and_truncated_commands_rejected(self):
        data = image(True)
        struct.pack_into('<H', data, 3042, 12)
        with self.assertRaises(ValueError):
            Metadata(data)
        with self.assertRaises(ValueError):
            Metadata(image()[:40])

    def test_changed_or_missing_method_fails_even_with_opt_in(self):
        required = [{'class': 'PNS', 'kind': '-', 'selector': 'post:', 'types': 'v24@0:8@16'}]
        for actual in ({}, {('PNS', '-', 'post:'): '@24@0:8@16'}):
            issues = compare_methods(actual, required)
            self.assertEqual(len(issues), 1)
            with self.assertRaises(ValueError):
                require_compatible({'static_compatible': False, 'problems': issues,
                                    'baseline_match': False}, allow_untested=True)

    def test_new_client_requires_opt_in_but_baseline_does_not(self):
        report = {'static_compatible': True, 'problems': [], 'baseline_match': False}
        with self.assertRaises(ValueError):
            require_compatible(report)
        require_compatible(report, True)
        require_compatible({**report, 'baseline_match': True})

    def test_library_manifest_mismatch_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            lib, manifest = root / 'mod.dylib', root / 'manifest.json'
            lib.write_bytes(b'original library')
            manifest.write_text(json.dumps({'format': 1, 'mode': 'region-aggressive',
                                           'library_sha256': sha256(lib),
                                           'compatibility': {'required_methods': [{}]}}))
            load_manifest(manifest, lib)
            lib.write_bytes(b'changed library')
            with self.assertRaises(ValueError):
                load_manifest(manifest, lib)

    def test_legacy_package_cannot_skip_version_guard(self):
        with self.assertRaisesRegex(ValueError, 'manifest'):
            package(Path('unused'), None, Path('unused-output'), allow_untested=True)


if __name__ == '__main__':
    unittest.main()
