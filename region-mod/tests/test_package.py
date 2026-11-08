import importlib.util
from pathlib import Path
import struct
import unittest

spec = importlib.util.spec_from_file_location("region_package", Path(__file__).parents[1] / "scripts/package.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def fixture():
    data = bytearray(4096)
    struct.pack_into("<8I", data, 0, 0xFEEDFACF, 0x100000C, 0, 2, 2, 176, 0, 0)
    struct.pack_into("<II", data, 32, 0x19, 152)
    struct.pack_into("<I", data, 32 + 64, 1)
    struct.pack_into("<I", data, 32 + 72 + 48, 2048)
    struct.pack_into("<6I", data, 184, 0x2C, 24, 2048, 128, 0, 0)
    data[2048:] = b"X" * 2048
    return bytes(data)


class PackageTests(unittest.TestCase):
    def test_release_cannot_mix_with_experiments(self):
        for options in ({'auth_probe': Path('probe')}, {'library': Path('region')},
                        {'mod_compatibility': 'store'}, {'bundle_identity': True},
                        {'keychain_compat': True}, {'control': True}):
            with self.subTest(options=options), self.assertRaises(ValueError):
                args = {'source': Path('unused'), 'library': None, 'output': Path('unused-output'),
                        'compatibility_library': Path('release')}
                args.update(options)
                module.package(**args)

    def test_compatibility_rejects_unknown_profile_or_missing_probe(self):
        for profile, probe in (("unknown", Path("probe")), ("full", None), ("store", None)):
            with self.subTest(profile=profile, probe=probe), self.assertRaises(ValueError):
                module.package(Path("unused"), None, Path("unused-output"),
                               auth_probe=probe, mod_compatibility=profile)

    def test_preserves_sections_and_existing_commands(self):
        original = fixture()
        result = module.inject(original)
        self.assertEqual(result[2048:], original[2048:])
        self.assertEqual(result[32:208], original[32:208])
        self.assertEqual(len(result), len(original))
        self.assertEqual(len(module.commands(result)), 3)
        with self.assertRaises(ValueError):
            module.inject(result)

    def test_rejects_occupied_padding(self):
        data = bytearray(fixture())
        data[210] = 1
        with self.assertRaises(ValueError):
            module.inject(data)

    def test_rejects_encrypted_images(self):
        data = bytearray(fixture())
        module.check_decrypted(data)
        struct.pack_into("<I", data, 200, 1)
        with self.assertRaises(ValueError):
            module.check_decrypted(data)

    def test_rejects_malformed_load_commands(self):
        data = bytearray(fixture())
        struct.pack_into("<I", data, 36, 0)
        with self.assertRaises(ValueError):
            module.inject(data)


if __name__ == "__main__":
    unittest.main()
