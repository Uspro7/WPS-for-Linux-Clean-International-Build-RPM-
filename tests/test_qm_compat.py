"""Focused checks for lossless QM alias generation."""
import importlib.util
from pathlib import Path
import struct
import unittest
import tempfile

spec = importlib.util.spec_from_file_location('wps_qm_compat', Path(__file__).resolve().parents[1] / 'src/wps_qm_compat.py')
compat = importlib.util.module_from_spec(spec)
spec.loader.exec_module(compat)


def catalog(entries):
    messages = bytearray()
    indices = []
    for context, source, translation in entries:
        indices.append((compat.elf_hash((source + context).encode()), len(messages)))
        text = translation.encode('utf-16-be')
        messages.extend(struct.pack('>BI', 3, len(text)) + text + b'\x01')
    hashes = b''.join(struct.pack('>II', *entry) for entry in sorted(indices))
    return compat.MAGIC + b''.join(struct.pack('>BI', tag, len(value)) + value
                                  for tag, value in [(compat.HASHES, hashes), (compat.MESSAGES, messages)])


class QmCompatTests(unittest.TestCase):
    def test_same_source_in_different_contexts_and_original_messages_preserved(self):
        original = catalog([('one', 'Home', '开始'), ('two', 'Home', '首页')])
        patched, count = compat.add_aliases(original, {('one', 'Home'), ('two', 'Home'), ('one', 'Missing')})
        self.assertEqual(count, 2)
        old_blocks, blocks = dict(compat.read_blocks(original)), dict(compat.read_blocks(patched))
        self.assertTrue(blocks[compat.MESSAGES].startswith(old_blocks[compat.MESSAGES]))
        originals = set(struct.iter_unpack('>II', old_blocks[compat.HASHES]))
        self.assertTrue(originals.issubset(set(struct.iter_unpack('>II', blocks[compat.HASHES]))))
        aliases = []
        for key, offset in struct.iter_unpack('>II', blocks[compat.HASHES]):
            if key == compat.elf_hash(b'Home'):
                fields = compat.read_message(blocks[compat.MESSAGES], offset)
                self.assertEqual(fields[6], [b'Home'])
                self.assertEqual(fields[8], [b''])
                aliases.append((fields[7][0], fields[3][0].decode('utf-16-be')))
        self.assertEqual(sorted(aliases), [(b'one', '开始'), (b'two', '首页')])
        again, count = compat.add_aliases(patched, {('one', 'Home'), ('two', 'Home')})
        self.assertEqual(count, 0)
        self.assertEqual(again, patched)

    def test_xml_preserves_multiline_button_keys(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'home.kuip'
            path.write_text('<shell tc="wpsongmani" component="wps"><mainwindow tc="mainwindow">'
                            '<commands tc="commands"><command text="@Format\nPainter"/></commands>'
                            '</mainwindow></shell>')
            queries = compat.resource_queries(Path(tmp))['wps']
            self.assertIn(('wpsongmani.mainwindow.commands', 'Format\nPainter'), queries)
            self.assertIn(('wpsongmani.mainwindow.commands', 'Format Painter'), queries)

    def test_invalid_qm_is_rejected(self):
        with self.assertRaises(ValueError):
            compat.add_aliases(b'not a qm', set())
        with self.assertRaises(ValueError):
            compat.read_blocks(compat.MAGIC + b'\x42\x00\x00\x00\x10short')


if __name__ == '__main__':
    unittest.main()
