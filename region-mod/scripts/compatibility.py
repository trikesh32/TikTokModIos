"""Conservative static check of selected Objective-C methods, not runtime proof.

Supports thin ARM64 metadata, including dyld chained pointer formats 2 and 6.
Unknown layouts fail closed and need investigation, not a guessed ABI.
"""
import hashlib
import json
import mmap
from pathlib import Path
import struct


def sha256(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


class Metadata:
    def __init__(self, data):
        self.data = data
        self.segments = []
        self.sections = {}
        self.chains = []
        self.chain_pages = {}
        fixups = None
        if self.unpack('<II', 0) != (0xFEEDFACF, 0x100000C):
            raise ValueError('Metadata requires a thin ARM64 Mach-O')
        count, size = self.unpack('<II', 16)
        end = 32 + size
        if end > len(data) or count > size // 8:
            raise ValueError('Invalid Mach-O commands')
        pos = 32
        for _ in range(count):
            cmd, length = self.unpack('<II', pos)
            if length < 8 or length % 8 or pos + length > end:
                raise ValueError('Invalid load command')
            if cmd == 0x80000034:
                fixups = self.unpack('<II', pos + 8)
            if cmd in (0x21, 0x2C):
                if length < 20 or self.unpack('<I', pos + 16)[0]:
                    raise ValueError('Encrypted Mach-O; provide a decrypted IPA')
            if cmd == 0x19:
                if length < 72:
                    raise ValueError('Truncated segment')
                vm, _, offset, size = self.unpack('<QQQQ', pos + 24)
                if offset + size > len(data):
                    raise ValueError('Segment outside file')
                self.segments.append((vm, offset, size))
                sections = self.unpack('<I', pos + 64)[0]
                if 72 + sections * 80 > length:
                    raise ValueError('Truncated sections')
                for index in range(sections):
                    entry = pos + 72 + index * 80
                    name = data[entry:entry + 16].split(b'\0')[0].decode('ascii')
                    if name == '__objc_classlist':
                        self.sections[name] = self.unpack('<QQ', entry + 32)
            pos += length
        if pos != end:
            raise ValueError('Load command size mismatch')
        self.base = min(vm for vm, offset, size in self.segments if offset == 0 and size)
        if fixups:
            self.load_chains(*fixups)

    def load_chains(self, offset, size):
        # Layout: Apple's mach-o/fixup-chains.h. Decode actual chain locations;
        # do not blindly mask arbitrary pointers into apparently valid addresses.
        end = offset + size
        if size < 28 or end > len(self.data):
            raise ValueError('Invalid chained fixups')
        version, starts = self.unpack('<II', offset)
        start = offset + starts
        if version or starts < 28 or start + 4 > end:
            raise ValueError('Unsupported chained fixups header')
        count = self.unpack('<I', start)[0]
        if count != len(self.segments) or start + 4 + 4 * count > end:
            raise ValueError('Invalid chained segment table')
        for i in range(count):
            relative = self.unpack('<I', start + 4 + 4 * i)[0]
            if not relative:
                continue
            entry = start + relative
            if entry < start + 4 + 4 * count or entry + 22 > end:
                raise ValueError('Invalid chain starts')
            length, page_size, fmt, vm_offset, _, pages = self.unpack('<IHHQIH', entry)
            if fmt not in (2, 6) or page_size not in (4096, 16384):
                raise ValueError('Unsupported chained pointer format/page size')
            if length < 22 + 2 * pages or entry + length > end:
                raise ValueError('Truncated page starts')
            vm, file_offset, file_size = self.segments[i]
            if vm != self.base + vm_offset or pages * page_size > file_size + page_size - 1:
                raise ValueError('Invalid chained segment range')
            self.chains.append((vm, file_size, page_size, fmt, entry + 22, pages))

    def chained_format(self, address):
        for vm, size, page_size, fmt, starts, pages in self.chains:
            if not vm <= address < vm + size:
                continue
            page = (address - vm) // page_size
            if page >= pages:
                return None
            key = (vm, page)
            if key not in self.chain_pages:
                first = self.unpack('<H', starts + page * 2)[0]
                locations = set()
                if first != 0xffff:
                    if first & 0x8000:
                        raise ValueError('Multiple chain starts need a new decoder')
                    pos = first
                    while True:
                        if pos + 8 > page_size:
                            raise ValueError('Chain escaped page')
                        location = vm + page * page_size + pos
                        raw = self.unpack('<Q', self.offset(location))[0]
                        locations.add(location)
                        step = ((raw >> 51) & 0xfff) * 4
                        if not step:
                            break
                        pos += step
                self.chain_pages[key] = locations
            return fmt if address in self.chain_pages[key] else None
        return None

    def unpack(self, fmt, offset):
        if offset < 0 or offset + struct.calcsize(fmt) > len(self.data):
            raise ValueError('Metadata outside file')
        return struct.unpack_from(fmt, self.data, offset)

    def offset(self, address):
        for vm, offset, size in self.segments:
            if vm <= address < vm + size:
                return offset + address - vm
        raise ValueError('Unresolved metadata pointer: ' + hex(address))

    def pointer(self, address):
        value = self.unpack('<Q', self.offset(address))[0]
        fmt = self.chained_format(address)
        if fmt:
            if value >> 63 or ((value >> 44) & 0x7f):
                raise ValueError('Bound or unsupported metadata pointer')
            value = ((value & 0xfffffffff) | (((value >> 36) & 0xff) << 56)) + (self.base if fmt == 6 else 0)
        if value:
            self.offset(value & ~7)
        return value

    def string(self, address):
        offset = self.offset(address)
        end = self.data.find(b'\0', offset, min(offset + 4096, len(self.data)))
        if end < 0:
            raise ValueError('Unterminated metadata string')
        return self.data[offset:end].decode('utf-8')

    def methods(self, targets):
        start, size = self.sections.get('__objc_classlist', (0, 0))
        if not start or size % 8 or size // 8 > 200000:
            raise ValueError('Invalid or missing Objective-C class list')
        rows = {}
        for i in range(size // 8):
            cls = self.pointer(start + i * 8)
            ro = self.pointer(cls + 32) & ~7
            name = self.string(self.pointer(ro + 24))
            if name not in targets:
                continue
            for base, kind in ((ro, '-'), (self.pointer(self.pointer(cls) + 32) & ~7, '+')):
                methods = self.pointer(base + 32)
                if not methods:
                    continue
                flags, count = self.unpack('<II', self.offset(methods))
                stride = (flags & 0xffff) & ~3
                small = bool(flags & 0x80000000)
                if count > 100000 or stride < (12 if small else 24):
                    raise ValueError('Invalid Objective-C method list')
                for j in range(count):
                    entry = methods + 8 + j * stride
                    if small:
                        sel, typ, _ = self.unpack('<iii', self.offset(entry))
                        selector = self.string(entry + sel if flags & 0x40000000 else self.pointer(entry + sel))
                        types = self.string(entry + 4 + typ)
                    else:
                        selector = self.string(self.pointer(entry))
                        types = self.string(self.pointer(entry + 8))
                    key = (name, kind, selector)
                    if key in rows and rows[key] != types:
                        raise ValueError('Ambiguous method metadata: ' + repr(key))
                    rows[key] = types
        return rows


def read_methods(path, targets):
    with Path(path).open('rb') as stream:
        with mmap.mmap(stream.fileno(), 0, access=mmap.ACCESS_READ) as data:
            return Metadata(data).methods(targets)


def compare_methods(actual, required):
    problems = []
    for method in required:
        key = (method['class'], method['kind'], method['selector'])
        found = actual.get(key)
        if found != method['types']:
            problems.append({**method, 'actual': found, 'reason': 'missing' if found is None else 'abi_changed'})
    return problems


def check_app(app, info, manifest):
    if info.get('CFBundleIdentifier') != manifest['bundle_id']:
        raise ValueError('Not an original TikTok bundle ID')
    contract = manifest['compatibility']
    core = app / 'Frameworks/MusicallyCore.framework/MusicallyCore'
    methods = read_methods(core, {r['class'] for r in contract['required_methods']})
    problems = compare_methods(methods, contract['required_methods'])
    core_hash = sha256(core)
    baseline = contract['baseline']
    known = (info.get('CFBundleShortVersionString') == baseline['version'] and
             info.get('CFBundleVersion') == baseline['build'] and core_hash == baseline['core_sha256'])
    return {'app_version': info.get('CFBundleShortVersionString'),
            'app_build': info.get('CFBundleVersion'), 'core_sha256': core_hash,
            'baseline_match': known, 'checked_methods': len(contract['required_methods']),
            'static_compatible': not problems, 'problems': problems,
            'runtime_verified': False,
            'scope': 'Selected methods in MusicallyCore only; no server/runtime guarantee'}


def load_manifest(path, library):
    manifest = json.loads(Path(path).read_text())
    if manifest.get('format') != 1 or manifest.get('mode') != 'region-aggressive':
        raise ValueError('Unsupported tweak manifest')
    if sha256(library) != manifest['library_sha256']:
        raise ValueError('Tweak library hash mismatch')
    if not manifest['compatibility']['required_methods']:
        raise ValueError('Empty compatibility contract')
    return manifest


def require_compatible(report, allow_untested=False):
    if not report['static_compatible']:
        raise ValueError('Required TikTok methods missing or changed: ' + json.dumps(report['problems']))
    if not report['baseline_match'] and not allow_untested:
        raise ValueError('New/unverified TikTok build: inspect the report, then use --allow-untested for a test IPA')
