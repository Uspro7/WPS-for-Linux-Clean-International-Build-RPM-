#!/usr/bin/env python3
"""Add legacy-Qt lookup aliases to official Chinese WPS QM resources.

The international 11.x XML UI requests translate(context, source, nullptr),
whereas the imported Chinese catalog indexes these strings by source+context.
Keep every original message and add explicit context/source aliases indexed by
source alone. Official translations are reused; obsolete ribbon labels have explicit overrides.
No executable is patched.
"""
import argparse
import re
from collections import defaultdict
from pathlib import Path
import struct
import xml.etree.ElementTree as ET

MAGIC = bytes.fromhex('3cb86418caef9c95cd211cbf60a1bddd')
HASHES, MESSAGES, CONTEXTS = 0x42, 0x69, 0x2F


def elf_hash(data):
    value = 0
    for byte in data:
        value = (value << 4) + byte
        high = value & 0xF0000000
        if high:
            value ^= high >> 24
        value &= ~high
    return value or 1


def read_blocks(data):
    if not data.startswith(MAGIC):
        raise ValueError('Invalid QM magic')
    blocks, pos = [], len(MAGIC)
    while pos < len(data):
        if pos + 5 > len(data):
            raise ValueError('Truncated QM block')
        tag, size = struct.unpack_from('>BI', data, pos)
        pos += 5
        if pos + size > len(data):
            raise ValueError('Truncated QM payload')
        blocks.append((tag, data[pos:pos + size]))
        pos += size
    return blocks


def read_message(data, offset):
    fields = defaultdict(list)
    while True:
        tag = data[offset]
        offset += 1
        if tag == 1:
            return fields
        size = struct.unpack_from('>I', data, offset)[0]
        offset += 4
        if tag == 5:  # Obsolete fixed-size hash, not a string.
            continue
        if size == 0xFFFFFFFF:  # Null QByteArray / QString.
            size = 0
        if offset + size > len(data):
            raise ValueError('Truncated QM message')
        fields[tag].append(bytes(data[offset:offset + size]))
        offset += size


def resource_queries(resource_dir):
    queries = defaultdict(set)
    def visit(node, context='', component='kso'):
        context = '.'.join(part for part in (context, node.get('tc', '')) if part)
        component = node.get('component', component)
        if component in ('wps', 'et', 'wpp', 'kso'):
            for value in node.attrib.values():
                if value.startswith('@') and '@' not in value[1:] and context:
                    queries[component].add((context, value[1:]))
        for child in node:
            visit(child, context, component)
    for path in sorted(resource_dir.rglob('*')):
        if path.suffix in ('.kui', '.kuip'):
            text = path.read_text(encoding='utf-8-sig')
            visit(ET.fromstring(text))
            # WPS preserves literal line breaks in UI attributes; ElementTree
            # normally folds them to spaces. Include both forms for old skins.
            def preserve_lines(match):
                return match.group(0).replace('\r\n', '&#10;').replace('\n', '&#10;').replace('\r', '&#10;')
            preserved = re.sub(r"(['\"])(@.*?)(\1)", preserve_lines, text, flags=re.DOTALL)
            if preserved != text:
                visit(ET.fromstring(preserved))
    return queries


def catalog_queries(path):
    blocks = dict(read_blocks(path.read_bytes()))
    queries = set()
    for _, offset in struct.iter_unpack('>II', blocks[HASHES]):
        fields = read_message(blocks[MESSAGES], offset)
        if 6 in fields and 7 in fields:
            queries.add(tuple(fields.get(tag, [b''])[0].decode('utf-8') for tag in (7, 6, 8)))
    return queries


def add_aliases(data, queries, overrides=None):
    blocks = read_blocks(data)
    block_map = dict(blocks)
    messages = bytearray(block_map[MESSAGES])
    indices = list(struct.iter_unpack('>II', block_map[HASHES]))
    by_hash = defaultdict(list)
    for key, offset in indices:
        by_hash[key].append(offset)

    queries = {(entry[0], entry[1], entry[2] if len(entry) == 3 else '') for entry in queries}
    overrides = overrides or {}

    def find(context, source, hash_suffix, comment):
        key = elf_hash(source + hash_suffix)
        for offset in by_hash[key]:
            fields = read_message(messages, offset)
            if 6 in fields and fields[6][0] != source:
                continue
            if 7 in fields and fields[7][0] != context:
                continue
            if fields.get(8, [b''])[0] not in (b'', comment):
                continue
            translations = fields.get(3, [])
            if translations and any(translations):
                return translations
        return None

    # When a newer catalog moved a command to a different context, use its
    # official translation only if all known contexts agree on that source.
    known = defaultdict(set)
    for context, source, comment in queries:
        translated = find(context.encode(), source.encode(), context.encode(), comment.encode())
        if translated:
            known[source].add(tuple(translated))

    count = 0
    for context_text, source_text, comment_text in sorted(queries):
        context, source, comment = (value.encode('utf-8') for value in (context_text, source_text, comment_text))
        if find(context, source, comment, comment):
            continue  # Do not override a working original translation.
        translations = find(context, source, context, comment)
        if not translations and (context_text, source_text, comment_text) in overrides:
            translations = [overrides[(context_text, source_text, comment_text)].encode('utf-16-be')]
        if not translations and len(known[source_text]) == 1:
            translations = next(iter(known[source_text]))
        if not translations:
            continue
        offset = len(messages)
        for tag, value in [(3, text) for text in translations] + [(6, source), (7, context), (8, comment)]:
            messages.extend(struct.pack('>BI', tag, len(value)) + value)
        messages.append(1)
        key = elf_hash(source + comment)
        indices.append((key, offset))
        by_hash[key].append(offset)
        count += 1
    if not count:
        return data, 0
    replacements = {HASHES: b''.join(struct.pack('>II', *entry) for entry in sorted(indices)),
                    MESSAGES: bytes(messages)}
    result = bytearray(MAGIC)
    for tag, original in blocks:
        if tag == CONTEXTS:
            # Optional acceleration table would reject newly added contexts.
            continue
        value = replacements.get(tag, original)
        result.extend(struct.pack('>BI', tag, len(value)) + value)
    return bytes(result), count


def patch_office(office):
    queries = resource_queries(office / 'res')
    common = set().union(*queries.values())
    total = 0
    for component in ('wps', 'et', 'wpp', 'kso', 'wpsoffice'):
        path = office / f'mui/zh_CN/{component}.qm'
        if not path.is_file():
            continue
        component_queries = common.copy() if component in ('kso', 'wpsoffice') else queries[component].copy()
        reference = office / f'mui/en_US/{component}.qm'
        if reference.is_file():
            component_queries.update(catalog_queries(reference))
        # 12.x removed this 11.x ribbon category; "Section" also means "节"
        # in other dialogs, so it must not use a context-free fallback.
        overrides = {(f'wps{skin}.mainwindow.commands', 'Section', ''): '章节'
                     for skin in ('ongmani', 'rainbow')} if component == 'wps' else {}
        if component == 'et':
            overrides = {('ongmani.ct_home', 'Format', ''): '格式',
                         ('etongmani.mainwindow.commands', 'EtTools', ''): '工具箱'}
            for context in ('classics.standard', 'etcommon.mainwindow.commands', 'ongmani.ct_data',
                            'ongmani.ct_home', 'popupmenu'):
                overrides[(context, 'AutoFilter', '')] = '自动筛选'
        data, count = add_aliases(path.read_bytes(), component_queries, overrides)
        if count:
            path.write_bytes(data)
        print(f'{component}.qm: {count} compatible UI translations')
        total += count
    return total


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('office', type=Path)
    patch_office(parser.parse_args().office)
