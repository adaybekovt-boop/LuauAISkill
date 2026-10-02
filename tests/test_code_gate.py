"""A missing filename or silent tool failure cannot produce TYPECHECKED evidence."""
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import check_code as code

class CodeGateTests(unittest.TestCase):
    def test_silent_nonzero_tool_exit_is_a_failure(self):
        with tempfile.TemporaryDirectory() as tmp:
            definitions = Path(tmp) / 'defs.luau'
            definitions.write_text('')
            with patch.object(code, 'DEFS', definitions), patch.object(code, 'tool', return_value='lsp'), \
                    patch.object(code.subprocess, 'run', return_value=subprocess.CompletedProcess([], 2, '', '')):
                errors = code.lsp_analyze([], Path(tmp))
                self.assertTrue(errors)
                self.assertIn('exited 2', errors[0])

    def test_unmatched_markdown_diagnostic_is_not_dropped(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / 'example.md'
            source.write_text('```luau\nlocal x: number = 1\n```\n')
            with patch.object(code, 'ROOT', root), patch.object(code, 'lsp_analyze', return_value=['global typechecker failure']):
                results = code.check_markdown([source])
                self.assertTrue(any(row['status'] == 'FAILED' for row in results))

    def test_unmatched_project_diagnostic_is_not_dropped(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            project = root / 'project'
            project.mkdir()
            (project / 'main.luau').write_text('--!strict\nreturn 1\n')
            with patch.object(code, 'ROOT', root), patch.object(code, 'link_lib', return_value=False), \
                    patch.object(code, 'unlink_lib'), patch.object(code, 'lsp_analyze', return_value=['global typechecker failure']):
                results = code.check_examples([project])
                self.assertTrue(any(row['status'] == 'FAILED' for row in results))

if __name__ == '__main__':
    unittest.main()
