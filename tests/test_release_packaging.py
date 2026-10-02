import importlib.util
from pathlib import Path
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('packaging_check', ROOT / 'tools/check_packaging.py')
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)

class PackagingTests(unittest.TestCase):
    def test_frontmatter_portable(self):
        package.portable_frontmatter((ROOT / 'SKILL.md').read_text())

    def test_nonportable_fields_rejected(self):
        with self.assertRaises(ValueError):
            package.portable_frontmatter('---\nname: x\ndescription: y\nmodel: private\n---\n')

    def test_archive_has_root_and_excludes_cache(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / 'skill.zip'
            package.build_zip(out)
            with zipfile.ZipFile(out) as archive:
                names = archive.namelist()
                self.assertIn('tk-luau-roblox/SKILL.md', names)
                self.assertFalse(any('/.git/' in n or '/.cache/' in n for n in names))
                self.assertTrue(all(n.startswith('tk-luau-roblox/') for n in names))

    def test_router_and_chapter_shape(self):
        self.assertLessEqual(len((ROOT / 'SKILL.md').read_text().splitlines()), 500)
        for path in (ROOT / 'handbook').rglob('*.md'):
            lines = path.read_text().splitlines()
            self.assertEqual(lines[2], '## TL;DR', path)
            self.assertEqual(sum(line.startswith('- ') for line in lines[3:8]), 5, path)

if __name__ == '__main__':
    unittest.main()
