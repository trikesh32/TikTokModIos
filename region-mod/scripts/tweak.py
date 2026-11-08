#!/usr/bin/env python3
"""Build a reusable tweak kit, inspect a client, or package a personal IPA."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

from compatibility import check_app, load_manifest, require_compatible, sha256
from package import package

SCRIPT = Path(__file__).resolve()
ROOT = SCRIPT.parents[1]


def source_version():
    text = (ROOT / 'src/RegionCompatibility.h').read_text()
    match = re.search(r'#ifdef TT_REGION_AGGRESSIVE\s+#define TRC_VERSION @"(\d+\.\d+\.\d+)"', text)
    if not match:
        raise ValueError('Cannot determine release version')
    return match[1]


def default_kit():
    if SCRIPT.with_name('manifest.json').exists():
        return SCRIPT.parent
    return ROOT / 'dist' / source_version()


def build(output=None):
    version = source_version()
    output = (output or ROOT / 'dist' / version).resolve()
    archive_path = Path(str(output) + '.zip')
    if output.exists() or archive_path.exists():
        raise ValueError('Release output exists; use --output with a new directory')
    subprocess.run(['bash', str(ROOT / 'scripts/build-compatibility.sh'), '--region-aggressive'], check=True)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.tweak-build-', dir=output.parent) as temp:
        kit = Path(temp) / output.name
        kit.mkdir()
        library = kit / 'TikTokCompatibility.dylib'
        shutil.copy2(ROOT / 'build/TikTokCompatibility-iOS.dylib', library)
        manifest = {'format': 1, 'name': 'TikTok Region', 'version': version,
                    'mode': 'region-aggressive', 'bundle_id': 'com.zhiliaoapp.musically',
                    'architecture': 'arm64', 'minimum_ios': '15.0',
                    'library_sha256': sha256(library),
                    'compatibility': json.loads((ROOT / 'compatibility/tiktok-47.6.0.json').read_text()),
                    'installation': 'AltStore Classic (--altstore) or the existing local signer'}
        (kit / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        for name in ('tweak.py', 'package.py', 'compatibility.py', 'source.py'):
            shutil.copy2(ROOT / 'scripts' / name, kit / name)
        shutil.copy2(ROOT / 'UPDATE.txt', kit / 'README.txt')
        shutil.copy2(ROOT / 'vendor/fishhook/LICENSE', kit / 'fishhook-LICENSE.txt')
        # Track source inputs without putting app binaries, signing material or
        # personal device state into the distributable kit.
        files = [p for folder in ('src', 'scripts', 'tests', 'compatibility', 'vendor')
                 for p in (ROOT / folder).rglob('*')
                 if p.is_file() and '__pycache__' not in p.parts]
        (kit / 'source-sha256.json').write_text(json.dumps(
            {str(p.relative_to(ROOT)): sha256(p) for p in sorted(files)}, indent=2) + '\n')
        (kit / 'SHA256.json').write_text(json.dumps(
            {p.name: sha256(p) for p in sorted(kit.iterdir())}, indent=2) + '\n')
        kit.rename(output)
    with zipfile.ZipFile(archive_path, 'w', zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(output.iterdir()):
            archive.write(path, output.name + '/' + path.name)
    return {'tweak': str(output), 'archive': str(archive_path), 'version': version}


def inspect(source, manifest):
    with zipfile.ZipFile(source) as archive, tempfile.TemporaryDirectory(prefix='tiktok-inspect-') as temp:
        entries = archive.namelist()
        if len(entries) != len(set(entries)):
            raise ValueError('Duplicate ZIP entries')
        plists = [n for n in entries if re.fullmatch(r'Payload/[^/]+\.app/Info\.plist', n)]
        if len(plists) != 1:
            raise ValueError('Expected one top-level app')
        info = plistlib.loads(archive.read(plists[0]))
        if any(info.get(k) for k in ('TTCompatibilityBuild', 'TTAuthProbeBuild', 'TRRegionLabBuild')):
            raise ValueError('Use an unmodified input IPA')
        prefix = plists[0][:-len('Info.plist')]
        relative = 'Frameworks/MusicallyCore.framework/MusicallyCore'
        app = Path(temp)
        core = app / relative
        core.parent.mkdir(parents=True)
        with archive.open(prefix + relative) as src, core.open('wb') as dst:
            shutil.copyfileobj(src, dst)
        return check_app(app, info, manifest)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    builder = commands.add_parser('build', help='Run native tests, compile and export a reusable kit')
    builder.add_argument('--output', type=Path)
    for name in ('inspect', 'pack'):
        command = commands.add_parser(name)
        command.add_argument('ipa', type=Path, help='Locally acquired, unmodified decrypted TikTok IPA')
        command.add_argument('--tweak', type=Path, help='Tweak kit directory; defaults to this release')
        if name == 'inspect':
            command.add_argument('--report', type=Path)
        else:
            command.add_argument('--output', type=Path, required=True)
            command.add_argument('--allow-untested', action='store_true')
            command.add_argument('--altstore', action='store_true', help='Prepare Classic signing metadata and Keychain grants')
            command.add_argument('--distribution-build', help='Unique numeric CFBundleVersion for feed updates')
    args = parser.parse_args()
    os.umask(0o077)
    if args.command == 'build':
        result = build(args.output)
    else:
        kit = (args.tweak or default_kit()).resolve()
        library = kit / 'TikTokCompatibility.dylib'
        manifest_path = kit / 'manifest.json'
        if not manifest_path.exists():
            raise ValueError('Tweak kit missing; run the build command once or pass --tweak DIR')
        manifest = load_manifest(manifest_path, library)
        if args.command == 'inspect':
            result = inspect(args.ipa, manifest)
            if args.report:
                args.report.write_text(json.dumps(result, indent=2) + '\n')
            print(json.dumps(result, indent=2))
            require_compatible(result, allow_untested=True)
            return
        result = package(args.ipa.resolve(), None, args.output.resolve(),
                         compatibility_library=library, region_profile='CA',
                         region_diagnostics=True, region_aggressive=True,
                         tweak_manifest=manifest_path, allow_untested=args.allow_untested,
                         altstore=args.altstore, distribution_build=args.distribution_build)
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, KeyError, zipfile.BadZipFile, subprocess.CalledProcessError) as error:
        print('Error: ' + str(error), file=sys.stderr)
        sys.exit(2)
