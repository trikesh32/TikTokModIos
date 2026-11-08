"""Package a locally acquired, verified decrypted IPA for AltStore signing."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import stat
import struct
import subprocess
import tempfile
import zipfile

MAGIC64 = b"\xcf\xfa\xed\xfe"
LOAD_DYLIB = 0xC
LIBRARY_PATH = "@executable_path/Frameworks/TikTokRegion.dylib"


def altstore_entitlements():
    # AltSign replaces the first component with the installing user's Team ID.
    # The remaining namespace is private to this mod, not TikTok's vendor groups.
    prefix = 'ALTSTORE00.com.zhiliaoapp.musically.altstore'
    return {'keychain-access-groups': [prefix] + [prefix + '.compat.' + label for label in
            ('main', 'test', 'shared', 'dev', 'chainlogin', 'chainassociate')]}


def commands(data):
    if len(data) < 32 or data[:4] != MAGIC64:
        raise ValueError("Expected a thin 64-bit little-endian Mach-O")
    count, size = struct.unpack_from("<II", data, 16)
    end = 32 + size
    if end > len(data) or count > size // 8:
        raise ValueError("Invalid load command bounds")
    pos = 32
    result = []
    for _ in range(count):
        if pos + 8 > end:
            raise ValueError("Truncated load command")
        cmd, length = struct.unpack_from("<II", data, pos)
        if length < 8 or length % 8 or pos + length > end:
            raise ValueError("Invalid load command size")
        result.append((cmd, pos, length))
        pos += length
    if pos != end:
        raise ValueError("Load command size mismatch")
    return result


def inject(data, library=LIBRARY_PATH):
    table = commands(data)
    if struct.unpack_from("<I", data, 4)[0] != 0x100000C:
        raise ValueError("Only ARM64 executables are supported")
    first_section = len(data)
    for cmd, pos, size in table:
        if cmd in (0xC, 0x18 | 0x80000000, 0x1F | 0x80000000):
            offset = struct.unpack_from("<I", data, pos + 8)[0]
            if offset >= size:
                raise ValueError("Invalid dylib path offset")
            name = data[pos + offset:pos + size].split(b"\0", 1)[0]
            if name == library.encode():
                raise ValueError("Module is already injected")
        if cmd == 0x19:
            if size < 72:
                raise ValueError("Invalid segment command")
            sections = struct.unpack_from("<I", data, pos + 64)[0]
            if 72 + sections * 80 > size:
                raise ValueError("Invalid section table")
            for index in range(sections):
                offset = struct.unpack_from("<I", data, pos + 72 + index * 80 + 48)[0]
                if offset:
                    first_section = min(first_section, offset)
    count, size = struct.unpack_from("<II", data, 16)
    name = library.encode() + b"\0"
    length = (24 + len(name) + 7) & ~7
    end = 32 + size
    if end + length > first_section or any(data[end:end + length]):
        raise ValueError("No verified zero-filled header padding for injection")
    command = struct.pack("<6I", LOAD_DYLIB, length, 24, 0, 0x10000, 0x10000) + name
    output = bytearray(data)
    output[end:end + length] = command.ljust(length, b"\0")
    struct.pack_into("<II", output, 16, count + 1, size + length)
    return bytes(output)


def check_decrypted(data):
    for cmd, pos, size in commands(data):
        if cmd in (0x21, 0x2C):
            if size < 20 or struct.unpack_from("<I", data, pos + 16)[0] != 0:
                raise ValueError("Encrypted or malformed Mach-O in input")


def package(source, library, output, control=False, auth_probe=None, keychain_compat=False, bundle_identity=False, mod_compatibility=None, compatibility_library=None, region_profile=None, region_diagnostics=False, region_requests=False, region_aggressive=False, tweak_manifest=None, allow_untested=False, altstore=False, distribution_build=None):
    manifest = None
    compatibility_report = None
    if tweak_manifest:
        from compatibility import load_manifest, check_app, require_compatible
        if not compatibility_library or not region_aggressive:
            raise ValueError('Tweak manifest requires the full region release')
        manifest = load_manifest(tweak_manifest, compatibility_library)
    if allow_untested and not manifest:
        raise ValueError('--allow-untested requires a verified tweak manifest')
    if altstore and not manifest:
        raise ValueError('AltStore requires the verified full-release manifest')
    if distribution_build and (not altstore or not all(c in '0123456789.' for c in distribution_build) or
                               any(not part for part in distribution_build.split('.')) or len(distribution_build) > 32):
        raise ValueError('Distribution build must be numeric dot-separated components in AltStore mode')
    if region_profile not in (None, 'CA') or (region_profile and not compatibility_library):
        raise ValueError('Carrier region requires the compatibility release and CA profile')
    if region_diagnostics and not region_profile:
        raise ValueError('Region observation requires --region-profile')
    if region_requests and not region_diagnostics:
        raise ValueError('Request experiment requires region diagnostics')
    if region_aggressive and (not region_diagnostics or region_requests):
        raise ValueError('Aggressive sources require diagnostics and exclude the old request rewriter')
    if sum((bool(library), bool(control), bool(auth_probe), bool(compatibility_library))) != 1:
        raise ValueError("Choose exactly one package mode")
    if compatibility_library and (keychain_compat or bundle_identity or mod_compatibility):
        raise ValueError("Release mode uses its fixed compatibility profile")
    if mod_compatibility not in (None, "store", "full") or (mod_compatibility and not auth_probe):
        raise ValueError("Compatibility profile requires auth probe and must be store or full")
    if output.exists():
        raise ValueError("Output exists; choose a new filename")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="region-package-", dir=output.parent) as tmp:
        root = Path(tmp)
        with zipfile.ZipFile(source) as archive:
            names = archive.namelist()
            if len(names) != len(set(names)):
                raise ValueError('Duplicate ZIP entries')
            for entry in archive.infolist():
                path = (root / entry.filename).resolve()
                if not path.is_relative_to(root.resolve()):
                    raise ValueError("Archive path traversal")
                mode = entry.external_attr >> 16
                if stat.S_ISLNK(mode):
                    raise ValueError("Unexpected symbolic link in IPA")
                archive.extract(entry, root)
                if path.is_file():
                    path.chmod(0o755 if mode & 0o111 else 0o644)
        apps = list((root / "Payload").glob("*.app"))
        if len(apps) != 1:
            raise ValueError("Expected exactly one app")
        app = apps[0]
        info_path = app / "Info.plist"
        info = plistlib.loads(info_path.read_bytes())
        if manifest:
            compatibility_report = check_app(app, info, manifest)
            output.with_suffix('.compatibility.json').write_text(json.dumps(compatibility_report, indent=2) + '\n')
            require_compatible(compatibility_report, allow_untested)
        elif info.get("CFBundleIdentifier") != "com.zhiliaoapp.musically" or info.get("CFBundleShortVersionString") != "47.6.0":
            raise ValueError("This prototype was inspected only against TikTok 47.6.0")
        removed_extensions = []
        for folder in ("PlugIns", "Watch", "AppClips"):
            directory = app / folder
            if directory.exists():
                removed_extensions.extend(p.name for p in directory.iterdir())
                shutil.rmtree(directory)
        for directory in list(app.rglob("SC_Info")) + list(app.rglob("_CodeSignature")):
            if directory.is_dir():
                shutil.rmtree(directory)
        # Metadata/receipts are not needed by AltStore and may identify a purchaser.
        for path in root.glob("iTunes*"):
            if path.is_file():
                path.unlink()
        for path in app.rglob("embedded.mobileprovision"):
            path.unlink()
        framework_dir = app / "Frameworks"
        framework_dir.mkdir(exist_ok=True)
        executable = app / info["CFBundleExecutable"]
        if compatibility_library:
            if any(info.get(key) for key in ('TRRegionLabBuild', 'TTAuthProbeBuild', 'TTCompatibilityBuild')):
                raise ValueError('Release requires an unmodified input')
            if any((framework_dir / name).exists() for name in ('TikTokAuthProbe.dylib', 'TikTokRegion.dylib', 'TikTokCompatibility.dylib')):
                raise ValueError('Release input already contains an injected module')
            shutil.copyfile(compatibility_library, framework_dir / 'TikTokCompatibility.dylib')
            executable.write_bytes(inject(executable.read_bytes(), '@executable_path/Frameworks/TikTokCompatibility.dylib'))
            # Match the compile-time constructor guard; reject a wrong module.
            has_region = b'TRCStartSettings' in compatibility_library.read_bytes()
            if has_region != bool(region_profile):
                raise ValueError('Module and requested region configuration do not match')
            if (b'TRDInstall' in compatibility_library.read_bytes()) != bool(region_diagnostics):
                raise ValueError('Module and region observation configuration do not match')
            if (b'TRQInstall' in compatibility_library.read_bytes()) != bool(region_requests):
                raise ValueError('Module and request experiment configuration do not match')
            if (b'TRSInstall' in compatibility_library.read_bytes()) != bool(region_aggressive):
                raise ValueError('Module and aggressive source configuration do not match')
            info['TTCompatibilityBuild'] = manifest['version'] if manifest else '1.1.0' if region_aggressive else '0.3.4' if region_requests else '0.3.2' if region_diagnostics else '0.3.1' if region_profile else '0.3.0'
            if region_profile:
                info['TTCarrierRegionProfile'] = region_profile
            info['TTModCompatibilityProfile'] = 'full'
            info['TTKeychainCompatBuild'] = '0.1.0'
            info['TTBundleIdentityBuild'] = '0.1.0'
        elif auth_probe:
            if any(info.get(key) for key in ('TRRegionLabBuild', 'TTAuthProbeBuild')):
                raise ValueError('Auth probe requires an unmodified input')
            shutil.copyfile(auth_probe, framework_dir / 'TikTokAuthProbe.dylib')
            executable.write_bytes(inject(executable.read_bytes(), '@executable_path/Frameworks/TikTokAuthProbe.dylib'))
            info['TTAuthProbeBuild'] = '0.2.6'
            if mod_compatibility:
                info['TTModCompatibilityProfile'] = mod_compatibility
            if keychain_compat:
                info['TTKeychainCompatBuild'] = '0.1.0'
            if bundle_identity:
                info['TTBundleIdentityBuild'] = '0.1.0'
        elif control:
            if (framework_dir / "TikTokRegion.dylib").exists() or "TRRegionLabBuild" in info:
                raise ValueError("Control requires a fresh unmodified input IPA")
            if LIBRARY_PATH.encode() in executable.read_bytes():
                raise ValueError("Control input already contains the module load command")
            # Preserve the vendor's name in the control: changing it is another
            # variable in authentication experiments on re-signed applications.
        else:
            shutil.copyfile(library, framework_dir / "TikTokRegion.dylib")
            executable.write_bytes(inject(executable.read_bytes()))
            info["CFBundleDisplayName"] = "TikTok Region"
            info["TRRegionLabBuild"] = "0.1.0"
        if altstore:
            info['TTDistribution'] = 'altstore-classic'
            info['CFBundleDisplayName'] = 'TikTok Mod'
            for key in ('TTKeychainCompatPrefix', 'TTSignedBundleIdentifier', 'ALTBundleIdentifier'):
                info.pop(key, None)
            if distribution_build:
                info['TTOriginalBuildVersion'] = info['CFBundleVersion']
                info['CFBundleVersion'] = distribution_build
        info_path.write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_BINARY))
        # Keep the original bundle ID; AltStore supplies its team-specific signing ID.
        images = []
        for path in app.rglob("*"):
            if not path.is_file():
                continue
            with path.open("rb") as stream:
                magic = stream.read(4)
            if magic == MAGIC64:
                check_decrypted(path.read_bytes())
                path.chmod(0o755)
                images.append(path)
            elif magic in (b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca", b"\xfe\xed\xfa\xce", b"\xce\xfa\xed\xfe"):
                raise ValueError("Unsupported Mach-O architecture; refusing an unchecked image")
        # Ad-hoc signatures make the archive internally checkable; AltStore replaces
        # them with the user's development signature and provisioning profile.
        for path in sorted(images, key=lambda p: len(p.parts), reverse=True):
            if path == executable:
                continue
            target = path.parent if path.parent.suffix == ".framework" else path
            subprocess.run(["codesign", "--force", "--sign", "-", str(target)], check=True, capture_output=True)
        signing = ["codesign", "--force", "--sign", "-"]
        if altstore:
            entitlements_file = root / 'altstore-entitlements.plist'
            entitlements_file.write_bytes(plistlib.dumps(altstore_entitlements()))
            signing += ['--entitlements', str(entitlements_file)]
        subprocess.run(signing + [str(app)], check=True, capture_output=True)
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True, capture_output=True)
        pending = root / "result.ipa"
        with zipfile.ZipFile(pending, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
            for path in sorted((root / "Payload").rglob("*")):
                if path.is_file():
                    archive.write(path, path.relative_to(root))
        with zipfile.ZipFile(pending) as archive:
            if archive.testzip() is not None:
                raise ValueError("Output ZIP integrity failure")
        pending.replace(output)
        output.chmod(0o600)
        with output.open("rb") as stream:
            digest = hashlib.file_digest(stream, "sha256").hexdigest()
        result = {"output": str(output), "sha256": digest, "bytes": output.stat().st_size,
                  "app_version": info.get('CFBundleShortVersionString'), "app_build": info.get('CFBundleVersion'), "mod_version": info.get('TTCompatibilityBuild') if compatibility_library else None if control or auth_probe else "0.1.0", "default_region": region_profile if compatibility_library else None if control or auth_probe else "CA",
                  "compatibility_check": compatibility_report,
                  "distribution": "altstore-classic" if altstore else "local-signer",
                  "minimum_os_version": info.get('MinimumOSVersion'),
                  "app_permissions": {'entitlements': list(altstore_entitlements()) if altstore else [],
                                      'privacy': {k: v for k, v in info.items() if 'UsageDescription' in k}},
                  "compatibility_version": info.get("TTCompatibilityBuild"),
                  "diagnostics_enabled": bool(auth_probe),
                  "region_observation_enabled": bool(region_diagnostics),
                  "region_request_rewrite_enabled": bool(region_requests),
                  "region_aggressive_sources_enabled": bool(region_aggressive),
                  "auth_probe_version": info.get('TTAuthProbeBuild'),
                  "keychain_compat_version": info.get('TTKeychainCompatBuild'),
                  "bundle_identity_version": info.get('TTBundleIdentityBuild'),
                  "mod_compatibility_profile": info.get('TTModCompatibilityProfile'),
                  "control_without_module": control,
                  "display_name": info.get("CFBundleDisplayName"),
                  "bundle_id": info["CFBundleIdentifier"],
                  "decrypted_images_checked": len(images), "removed_extensions": removed_extensions,
                  "adhoc_signature_verified": True, "zip_crc_verified": True, "device_tested": False}
        output.with_suffix(".verification.json").write_text(json.dumps(result, indent=2) + "\n")
        return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--library", type=Path)
    parser.add_argument("--compatibility-library", type=Path, help="Build the compatibility release without authentication diagnostics")
    parser.add_argument("--region-profile", choices=('CA',), help="Enable 0.3.1 client carrier/region experiment; requires a --region module build")
    parser.add_argument("--region-diagnostics", action='store_true', help="0.3.2 bounded in-memory region observations; requires --region-profile")
    parser.add_argument("--region-requests", action='store_true', help="0.3.4 content request region experiment; requires --region-diagnostics")
    parser.add_argument("--region-aggressive", action='store_true', help="1.0.2 persistent native settings menu, selectable regions and PNS support; excludes --region-requests")
    parser.add_argument("--control", action="store_true", help="Package without injecting any region module")
    parser.add_argument("--auth-probe", type=Path, help="Inject only the iOS authentication diagnostic module")
    parser.add_argument("--keychain-compat", action="store_true", help="With --auth-probe, remap known vendor Keychain groups to this signing identity")
    parser.add_argument("--bundle-identity", action="store_true", help="With --auth-probe, test the original ID through main NSBundle getters")
    parser.add_argument("--mod-compatibility", choices=("store", "full"), help="Opt-in App Store/environment getter compatibility; requires --auth-probe")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument('--tweak-manifest', type=Path, help='Verified release bundle manifest; enables static checks for new clients')
    parser.add_argument('--allow-untested', action='store_true', help='Permit a new client only after required ABI checks pass')
    parser.add_argument('--altstore', action='store_true')
    parser.add_argument('--distribution-build')
    args = parser.parse_args()
    if sum((args.control, bool(args.library), bool(args.auth_probe), bool(args.compatibility_library))) != 1:
        parser.error("Choose exactly one of --control, --library, --auth-probe, --compatibility-library")
    if args.keychain_compat and not args.auth_probe:
        parser.error('--keychain-compat requires --auth-probe')
    if args.bundle_identity and not args.auth_probe:
        parser.error('--bundle-identity requires --auth-probe')
    if args.mod_compatibility and not args.auth_probe:
        parser.error("--mod-compatibility requires --auth-probe")
    os.umask(0o077)
    print(json.dumps(package(args.input.resolve(), args.library.resolve() if args.library else None, args.output.resolve(), args.control,
                             args.auth_probe.resolve() if args.auth_probe else None, args.keychain_compat, args.bundle_identity, args.mod_compatibility,
                             args.compatibility_library.resolve() if args.compatibility_library else None, args.region_profile, args.region_diagnostics, args.region_requests, args.region_aggressive,
                             args.tweak_manifest, args.allow_untested, args.altstore, args.distribution_build)))
