#!/usr/bin/env python3
"""Read bounded NPK metadata; never execute, extract, repack or install its files.

Container/object layout reference:
https://lxr.openwrt.org/source/firmware-utils/src/npk_pack_kernel.c
This is a structural inspector, not a vendor signature verifier or boot validator.
"""
import argparse
import hashlib
import json
import lzma
from pathlib import Path
import re
import struct
import zlib

MAX_BYTES = 64 * 1024 * 1024
MAX_RECORDS = 4096
MAGIC = b'\x1e\xf1\xd0\xba'


def digest(data):
    return {'size_bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}


def read_bounded(path):
    with Path(path).open('rb') as stream:
        data = stream.read(MAX_BYTES + 1)
    if len(data) > MAX_BYTES:
        raise ValueError('Input exceeds size limit')
    return data


def parts(data):
    if len(data) < 8 or data[:4] != MAGIC:
        raise ValueError('Invalid NPK header')
    if len(data) > MAX_BYTES or struct.unpack_from('<I', data, 4)[0] != len(data) - 8:
        raise ValueError('Invalid NPK length')
    offset, count = 8, 0
    while offset < len(data):
        count += 1
        if count > MAX_RECORDS or len(data) - offset < 6:
            raise ValueError('Invalid part header/count')
        kind, size = struct.unpack_from('<HI', data, offset)
        end = offset + 6 + size
        if end > len(data):
            raise ValueError('Truncated part')
        yield kind, offset, data[offset + 6:end]
        offset = end


def objects(payload):
    decoder = zlib.decompressobj()
    try:
        data = decoder.decompress(payload, MAX_BYTES + 1)
    except zlib.error as error:
        raise ValueError('Invalid zlib stream') from error
    if len(data) > MAX_BYTES or not decoder.eof or decoder.unused_data:
        raise ValueError('Incomplete, oversized or trailing zlib stream')
    offset, count = 0, 0
    while offset < len(data):
        count += 1
        if count > MAX_RECORDS or len(data) - offset < 30:
            raise ValueError('Invalid object header/count')
        mode = struct.unpack_from('<H', data, offset)[0]
        size, name_size = struct.unpack_from('<IH', data, offset + 24)
        start = offset + 30 + name_size
        end = start + size
        if not name_size or end > len(data):
            raise ValueError('Invalid object length')
        # Names remain JSON strings only. Never use an archive name as a local path.
        name = data[offset + 30:start].decode('utf-8', errors='replace')
        yield name, mode, data[start:end]
        offset = end


def inspect_kernel(data):
    result = {'vendor_file_only': True, 'boot_compatibility_verified': False}
    if len(data) >= 52 and data[:7] == b'\x7fELF\x01\x02\x01':
        result.update(elf_class=32, byte_order='big',
                      elf_machine=struct.unpack_from('>H', data, 18)[0],
                      elf_entry_point=hex(struct.unpack_from('>I', data, 24)[0]))
    streams = []
    candidates = list(re.finditer(b'\xfd7zXZ\x00', data))
    if len(candidates) > 16:
        raise ValueError('Too many embedded XZ candidates')
    total = 0
    for match in candidates:
        try:
            decoder = lzma.LZMADecompressor(memlimit=128 * 1024 * 1024)
            raw = decoder.decompress(data[match.start():], max_length=MAX_BYTES - total + 1)
        except lzma.LZMAError:
            continue  # Magic bytes may occur in code rather than an XZ stream.
        total += len(raw)
        if total > MAX_BYTES:
            raise ValueError('Embedded decompression exceeds limit')
        if not decoder.eof:
            continue
        version = re.search(rb'Linux version [\x20-\x7e]{1,250}', raw)
        streams.append({
            'offset': match.start(), **digest(raw),
            'linux_version_string': version.group().decode('ascii') if version else None,
            'cpio_newc_magic': raw.startswith(b'070701'),
            'embedded_config_marker_found': b'IKCFG_ST' in raw,
            'candidate_strings': [s for s in ('ccs112', 'ccs112r4', 'spi-poe-pse',
                                             'music-spi-nand', 'MUSIC-IRQ')
                                  if s.encode() in raw],
        })
    result['embedded_xz_streams'] = streams
    return result


def inspect(data):
    report = {**digest(data), 'vendor_signature_verified': False,
              'installable_airlink_firmware': False, 'parts': [], 'files': []}
    expanded = 0
    for kind, offset, payload in parts(data):
        report['parts'].append({'type': kind, 'offset': offset, **digest(payload)})
        if kind == 4:
            # Bound the number of full decompressions as well as each stream.
            expanded += 1
            if expanded > 16:
                raise ValueError('Too many file containers')
            for name, mode, content in objects(payload):
                entry = {'name': name, 'mode': oct(mode), **digest(content)}
                if name == 'boot/kernel':
                    entry['inspection'] = inspect_kernel(content)
                report['files'].append(entry)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('npk', type=Path)
    parser.add_argument('--compare', type=Path, help='Separately obtained vendor package')
    args = parser.parse_args()
    try:
        data = read_bounded(args.npk)
        report = inspect(data)
        if args.compare:
            reference = read_bounded(args.compare)
            report['comparison'] = {**digest(reference), 'byte_identical': data == reference}
    except (OSError, ValueError) as error:
        parser.exit(1, f'Inspection failed: {error}\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
