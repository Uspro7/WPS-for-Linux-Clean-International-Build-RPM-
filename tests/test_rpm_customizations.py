"""Focused regression checks for the three requested RPM customizations."""
import os
import json
import sys
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
STAGE = ROOT / 'build/repack'
LOCALE_HELPER = ROOT / 'src/wps-locale.sh'
FONTS = {'symbol.ttf': 'Symbol', 'wingding.ttf': 'Wingdings',
         'WINGDNG2.ttf': 'Wingdings 2', 'WINGDNG3.ttf': 'Wingdings 3',
         'WEBDINGS.TTF': 'Webdings', 'mtextra.ttf': 'MT Extra'}


class LocaleTests(unittest.TestCase):
    def apply_locale(self, home, config_root=None):
        self.assertTrue(LOCALE_HELPER.is_file(), 'Chinese startup helper is missing')
        env = {**os.environ, 'HOME': str(home), 'LC_ALL': 'C', 'LANGUAGE': 'en_US'}
        env.pop('XDG_CONFIG_HOME', None)
        if config_root:
            env['XDG_CONFIG_HOME'] = str(config_root)
        subprocess.run(['sh', '-c', '. "$1"; test "$LANGUAGE" = zh_CN:zh',
                        'sh', str(LOCALE_HELPER)], env=env, check=True)

    def test_new_user_and_custom_config_home(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            config_root = home / 'custom config'
            self.apply_locale(home, config_root)
            self.assertEqual((config_root / 'Kingsoft/Office.conf').read_text(),
                             '[6.0]\nlanguages=zh_CN\n')
            self.assertFalse((home / '.config/Kingsoft/Office.conf').exists())

    def test_existing_config_preserved_and_idempotent(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            config = home / '.config/Kingsoft/Office.conf'
            config.parent.mkdir(parents=True)
            original = '[6.0]\nlanguages=en_US\ncommon\\Backup\\EnableIncBackup=1\n[other]\nlanguages=en_US\nkeep=1\n'
            config.write_text(original)
            self.apply_locale(home)
            expected = original.replace('languages=en_US', 'languages=zh_CN', 1)
            self.assertEqual(config.read_text(), expected)
            self.assertEqual(Path(str(config) + '.linuxwps-backup').read_text(), original)
            stamp = config.stat().st_mtime_ns
            self.apply_locale(home)
            self.assertEqual(config.stat().st_mtime_ns, stamp)
            self.assertEqual(Path(str(config) + '.linuxwps-backup').read_text(), original)

    def test_existing_config_without_office_section(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            config = home / '.config/Kingsoft/Office.conf'
            config.parent.mkdir(parents=True)
            config.write_text('[other]\nkeep=1\n')
            self.apply_locale(home)
            self.assertIn('[6.0]\nlanguages=zh_CN', config.read_text())
            self.assertIn('[other]\nkeep=1', config.read_text())


class PayloadTests(unittest.TestCase):
    def test_actual_qt_ribbon_translations_without_disambiguation(self):
        office = STAGE / 'opt/kingsoft/wps-office/office6'
        queries, expected = [], []
        for component in ['wps', 'et', 'wpp']:
            for source, chinese in [('Home', '开始'), ('Insert', '插入')]:
                queries.append([component, f'{component}ongmani.mainwindow.commands', source, None])
                expected.append(chinese)
            for source, chinese in [('Paste', '粘贴'), ('Font', '字体')]:
                queries.append([component, 'ongmani.ct_home', source, None])
                expected.append(chinese)
        for query, chinese in [
            (['wps', 'wpsongmani.mainwindow.commands', 'Page Layout', None], '页面'),
            (['wps', 'wpsongmani.mainwindow.commands', 'Section', None], '章节'),
            (['wps', 'wpsongmani.mainwindow.commands', 'Format\nPainter', None], '格式刷'),
            (['wps', 'ongmani.ct_section', 'Header and\nFooter', None], '页眉页脚'),
            (['et', 'ongmani.ct_home', 'AutoFilter', None], '自动筛选'),
            (['et', 'ongmani.ct_home', 'Format', None], '格式'),
            (['et', 'etongmani.mainwindow.commands', 'EtTools', None], '工具箱'),
            (['kso', 'KRbTabFileButton', 'Menu', None], '文件'),
            (['kso', 'KRibbonFindCmdWidget', 'Find Commands', None], '查找命令'),
            (['wpp', 'ongmani.ct_home', 'From Current\nSlide', None], '当页开始'),
            (['wpp', 'wpp_wppcore', 'Click to add first slide', None], '单击此处添加第一张幻灯片'),
        ]:
            queries.append(query)
            expected.append(chinese)
        env = {**os.environ, 'LD_LIBRARY_PATH': str(office)}
        result = subprocess.run([sys.executable, str(ROOT / 'tests/qt_translation_probe.py'), str(office)],
                                input=json.dumps(queries), text=True, capture_output=True, env=env, check=True)
        for query, actual, chinese in zip(queries, json.loads(result.stdout), expected):
            with self.subTest(component=query[0], context=query[1], source=query[2]):
                self.assertEqual(actual, chinese)

    def test_six_real_font_families(self):
        for filename, family in FONTS.items():
            font = STAGE / 'usr/share/fonts/wps-office' / filename
            with self.subTest(font=filename):
                self.assertTrue(font.is_file(), f'Missing formula font: {family}')
                actual = subprocess.check_output(['fc-scan', '--format', '%{family}', str(font)], text=True)
                self.assertIn(family, actual.split(','))

    def test_pdf_application_removed_but_export_library_preserved(self):
        for filename in ['usr/bin/wpspdf', 'usr/share/applications/wps-office-pdf.desktop',
                         'opt/kingsoft/wps-office/desktops/wps-office-pdf.desktop',
                         'opt/kingsoft/wps-office/office6/wpspdf']:
            with self.subTest(path=filename):
                self.assertFalse((STAGE / filename).exists(), f'PDF app still present: {filename}')
        self.assertTrue((STAGE / 'opt/kingsoft/wps-office/office6/libqpdfpaint.so').is_file())

    def test_all_three_launchers_use_chinese_helper(self):
        for binary in ['wps', 'wpset', 'wpswpp']:
            with self.subTest(binary=binary):
                script = (STAGE / 'usr/bin' / binary).read_text()
                self.assertIn(". '/opt/kingsoft/wps-office/office6/wps-locale.sh'", script)
        for component in ['wps', 'et', 'wpp', 'kso']:
            self.assertTrue((STAGE / f'opt/kingsoft/wps-office/office6/mui/zh_CN/{component}.qm').is_file())


if __name__ == '__main__':
    unittest.main()
