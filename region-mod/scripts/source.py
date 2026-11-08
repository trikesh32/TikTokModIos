"""Generate an AltStore Classic feed from a checked, ad-hoc release IPA."""
import argparse
import datetime
import json
from pathlib import Path
import plistlib
import re
from urllib.parse import urlsplit
import zipfile

from compatibility import sha256


def https(value):
    url = urlsplit(value)
    if url.scheme != 'https' or not url.hostname or url.username or url.password or url.fragment:
        raise ValueError('Use a public HTTPS URL without credentials or fragments')
    return value


def generate(ipa, download, icon, date, existing=None):
    datetime.datetime.fromisoformat(date.replace('Z', '+00:00'))
    report = json.loads(ipa.with_suffix('.verification.json').read_text())
    if report['sha256'] != sha256(ipa) or report['distribution'] != 'altstore-classic':
        raise ValueError('IPA does not match an AltStore packaging report')
    if not report['adhoc_signature_verified'] or not report['zip_crc_verified']:
        raise ValueError('Release verification incomplete')
    with zipfile.ZipFile(ipa) as archive:
        names = [n for n in archive.namelist() if re.fullmatch(r'Payload/[^/]+\.app/Info.plist', n)]
        if len(names) != 1:
            raise ValueError('Expected one app')
        if any(n.endswith('embedded.mobileprovision') for n in archive.namelist()):
            raise ValueError('Do not distribute a personal provisioning profile')
        info = plistlib.loads(archive.read(names[0]))
    if info['CFBundleIdentifier'] != 'com.zhiliaoapp.musically' or info['TTDistribution'] != 'altstore-classic':
        raise ValueError('Not a neutral AltStore IPA')
    for field, key in [('CFBundleVersion', 'app_build'), ('CFBundleShortVersionString', 'app_version')]:
        if info[field] != report[key]:
            raise ValueError('Version/report mismatch')
    version = {'version': info['CFBundleShortVersionString'], 'buildVersion': info['CFBundleVersion'],
               'marketingVersion': f"{info['CFBundleShortVersionString']} · Mod {info['TTCompatibilityBuild']} beta",
               'date': date, 'downloadURL': https(download), 'size': ipa.stat().st_size,
               'minOSVersion': max(info.get('MinimumOSVersion', '15.0'), '15.0', key=lambda v: tuple(map(int, v.split('.')))),
               'localizedDescription': 'AltStore Classic test release. Region selection and native settings. Installation through Classic still needs device confirmation.'}
    old = []
    if existing:
        old = existing['apps'][0]['versions']
        if any(v['version'] == version['version'] and v['buildVersion'] == version['buildVersion'] for v in old):
            raise ValueError('Source already contains this version/build')
    return {'name': 'TikTokModIos', 'identifier': 'io.github.trikesh32.tiktokmodios',
            'subtitle': 'TikTok Region for AltStore Classic', 'website': 'https://github.com/trikesh32/TikTokModIos',
            'iconURL': https(icon), 'tintColor': '#167D8D',
            'apps': [{'name': 'TikTok Mod', 'bundleIdentifier': info['CFBundleIdentifier'],
                      'developerName': 'TikTokModIos contributors (independent modification)',
                      'localizedDescription': 'Unofficial region modification. CA, FR, DE, GB, US and KZ. Open Settings and privacy → Настройки мода. Restart after changing region. AltStore installation is currently experimental; not affiliated with TikTok.',
                      'iconURL': https(icon), 'category': 'social', 'versions': [version] + old,
                      'appPermissions': report['app_permissions']}], 'news': []}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ipa', type=Path, required=True)
    parser.add_argument('--download-url', required=True)
    parser.add_argument('--icon-url', required=True)
    parser.add_argument('--date', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--previous', type=Path)
    args = parser.parse_args()
    if args.output.exists():
        parser.error('Output exists; generate to a new file and review before publishing')
    result = generate(args.ipa, args.download_url, args.icon_url, args.date,
                      json.loads(args.previous.read_text()) if args.previous else None)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
